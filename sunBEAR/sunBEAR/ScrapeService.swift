import Foundation
import SwiftData

@MainActor
@Observable
final class ScrapeService {
    static let maximumSearchPages = 10
    var isRunning = false
    var status = "Ready"
    var completed = 0
    var total = 0
    private var task: Task<Void, Never>?
    private let pageLoader = WebPageLoader()

    @discardableResult
    func start(searchURL: URL, destination: URL, shouldDownloadPDFs: Bool, pageLimit: Int, context: ModelContext) -> ScrapeSession? {
        guard !isRunning else { return nil }
        guard let source = ScrapeSource.source(for: searchURL) else {
            status = "Choose a supported source's search-results URL."
            return nil
        }
        let pageLimit = Self.clampedPageLimit(pageLimit)
        isRunning = true
        completed = 0
        total = 0
        let startedAt = Date.now
        let sessionName = ScrapeFolderNaming.folderName(for: searchURL, date: startedAt)
        let session = ScrapeSession(name: sessionName, searchURL: searchURL.absoluteString, folderPath: destination.appendingPathComponent(sessionName).path, startedAt: startedAt)
        context.insert(session)
        task = Task {
            let hasAccess = destination.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { destination.stopAccessingSecurityScopedResource() }
                isRunning = false
            }
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let sessionFolder = uniqueURL(destination.appendingPathComponent(sessionName, isDirectory: true))
                try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
                session.folderPath = sessionFolder.path
                status = "Created \(sessionFolder.lastPathComponent)"
                var pageURL: URL? = searchURL
                var visitedPages = Set<URL>()
                var documentURLs: [URL] = []
                while let current = pageURL, visitedPages.count < pageLimit, visitedPages.insert(current).inserted {
                    status = "Reading search page \(visitedPages.count)…"
                    session.pagesScraped = visitedPages.count
                    let page = try await fetchHTML(current)
                    let html = page.html
                    if source == .cia, current.path.contains("advanced-search"), !page.finalURL.path.contains("advanced-search") {
                        throw ScrapeError.searchRedirected(page.finalURL)
                    }
                    switch source {
                    case .cia:
                        documentURLs.append(contentsOf: CIAHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                        pageURL = CIAHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    case .jstor:
                        documentURLs.append(contentsOf: JSTORHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                        pageURL = JSTORHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    case .eric:
                        documentURLs.append(contentsOf: ERICHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                        pageURL = ERICHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    case .pubmed:
                        documentURLs.append(contentsOf: PubMedHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                        pageURL = PubMedHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    case .nara:
                        documentURLs.append(contentsOf: NARAHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                        pageURL = NARAHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    }
                    documentURLs = Array(Set(documentURLs)).sorted { $0.absoluteString < $1.absoluteString }
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(350))
                }

                total = documentURLs.count
                for (index, url) in documentURLs.enumerated() {
                    status = "Scraping \(index + 1) of \(total)…"
                    let html = try await fetchHTML(url).html
                    let scraped: ScrapedDocument
                    switch source {
                    case .cia: scraped = CIAHTMLParser.document(from: html, url: url)
                    case .jstor: scraped = JSTORHTMLParser.document(from: html, url: url)
                    case .eric: scraped = ERICHTMLParser.document(from: html, url: url)
                    case .pubmed:
                        var document = PubMedHTMLParser.document(from: html, url: url)
                        if let pmcURL = PubMedHTMLParser.pmcArticleURL(in: html, baseURL: url),
                           let pmcPage = try? await fetchHTML(pmcURL) {
                            document.pdfURLs.append(contentsOf: PubMedHTMLParser.pdfURLs(in: pmcPage.html, baseURL: pmcPage.finalURL))
                            document.pdfURLs = Array(Set(document.pdfURLs)).sorted { $0.absoluteString < $1.absoluteString }
                        }
                        scraped = document
                    case .nara: scraped = NARAHTMLParser.document(from: html, url: url)
                    }
                    let item = makeItem(scraped)
                    item.session = session
                    context.insert(item)
                    if shouldDownloadPDFs {
                        do {
                            item.localPDFPaths = try await downloadPDFs(scraped.pdfURLs, for: item, to: sessionFolder)
                        } catch {
                            item.downloadError = error.localizedDescription
                        }
                    }
                    try context.save()
                    completed = index + 1
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(500))
                }
                session.isComplete = true
                try context.save()
                let mode = shouldDownloadPDFs ? "with PDFs" : "metadata only"
                status = total == 0 ? "No document links found in \(session.pagesScraped) page(s)" : "Finished: \(completed) documents (\(mode)) from \(session.pagesScraped) page(s) in \(sessionFolder.lastPathComponent)"
            } catch is CancellationError {
                status = "Stopped after \(completed) documents"
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
        return session
    }

    func cancel() { task?.cancel() }

    static func clampedPageLimit(_ value: Int) -> Int {
        min(max(value, 1), maximumSearchPages)
    }

    private func fetchHTML(_ url: URL) async throws -> (html: String, finalURL: URL) {
        try await pageLoader.html(at: url)
    }

    private func downloadPDFs(_ urls: [URL], for item: Item, to folder: URL) async throws -> [String] {
        var paths: [String] = []
        let cookies = await pageLoader.cookies()
        // Populate URLSession's cookie jar as well as the initial request. This
        // keeps the authenticated JSTOR session attached across its redirects.
        for cookie in cookies { HTTPCookieStorage.shared.setCookie(cookie) }
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15",
            "Accept": "application/pdf,text/html;q=0.8,*/*;q=0.5"
        ]
        let downloadSession = URLSession(configuration: configuration)
        defer { downloadSession.finishTasksAndInvalidate() }
        for (index, url) in urls.enumerated() {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            request.setValue(item.recordURL, forHTTPHeaderField: "Referer")
            let matchingCookies = cookies.filter { cookie in
                let host = url.host?.lowercased() ?? ""
                let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                return host == domain || host.hasSuffix(".\(domain)")
            }
            if let cookieHeader = HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"] {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            let (temporary, response) = try await downloadSession.download(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let signature = try Data(contentsOf: temporary, options: [.mappedIfSafe]).prefix(5)
            guard String(decoding: signature, as: UTF8.self) == "%PDF-" else {
                throw ScrapeError.notPDF(requested: url, returned: http.url, contentType: http.value(forHTTPHeaderField: "Content-Type"))
            }
            let original = url.lastPathComponent.removingPercentEncoding ?? "document-\(index + 1).pdf"
            let filename = original.lowercased().hasSuffix(".pdf") ? original : "\(original).pdf"
            let fallback = item.documentNumber.isEmpty ? "document-\(index + 1).pdf" : "\(item.documentNumber)-\(index + 1).pdf"
            let usableFilename = filename.isEmpty ? fallback : filename
            let target = uniqueURL(folder.appendingPathComponent(safeName(usableFilename)))
            try FileManager.default.moveItem(at: temporary, to: target)
            paths.append(target.path)
            try Task.checkCancellation()
        }
        return paths
    }

    private func makeItem(_ value: ScrapedDocument) -> Item {
        let f = value.fields
        return Item(title: value.title, documentType: f["Document Type"] ?? "", collection: f["Collection"] ?? "", documentNumber: f["Document Number (FOIA) /ESDN (CREST)"] ?? "", releaseDecision: f["Release Decision"] ?? "", originalClassification: f["Original Classification"] ?? "", pageCount: Int(f["Document Page Count"] ?? "") ?? 0, documentCreationDate: f["Document Creation Date"] ?? "", documentReleaseDate: f["Document Release Date"] ?? "", sequenceNumber: f["Sequence Number"] ?? "", publicationDate: f["Publication Date"] ?? "", contentType: f["Content Type"] ?? "", caseNumber: f["Case Number"] ?? "", recordURL: value.recordURL.absoluteString, pdfURLs: value.pdfURLs.map(\.absoluteString), body: value.body)
    }

    private func safeName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        let name = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(name.prefix(180)).isEmpty ? "document" : String(name.prefix(180))
    }

    private func uniqueURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            var candidate = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(n)")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}

enum ScrapeFolderNaming {
    static func folderName(for url: URL, date: Date) -> String {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let preferredKeys = ["keyword", "sm_field_document_number", "sm_field_case_number", "sm_field_content_type"]
        let values = preferredKeys.compactMap { key in
            query.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let source = ScrapeSource.source(for: url)
        let jstorQuery = query.first(where: { $0.name.caseInsensitiveCompare("Query") == .orderedSame })?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchName: String
        if let jstorQuery, !jstorQuery.isEmpty {
            searchName = "JSTOR - \(jstorQuery)"
        } else if source == .eric,
                  let ericQuery = query.first(where: { $0.name.caseInsensitiveCompare("q") == .orderedSame })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ericQuery.isEmpty {
            searchName = "ERIC - \(ericQuery)"
        } else if source == .pubmed,
                  let pubmedQuery = query.first(where: { $0.name.caseInsensitiveCompare("term") == .orderedSame })?.value.map({
                      $0.replacingOccurrences(of: "+", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                  }),
                  !pubmedQuery.isEmpty {
            searchName = "PubMed - \(pubmedQuery)"
        } else if source == .nara,
                  let naraQuery = query.first(where: { $0.name.caseInsensitiveCompare("q") == .orderedSame })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !naraQuery.isEmpty {
            searchName = "National Archives - \(naraQuery)"
        } else if !values.isEmpty {
            searchName = values.joined(separator: " - ")
        } else {
            searchName = "\(source?.title ?? "Web") Search"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "\(safe(searchName)) - \(formatter.string(from: date))"
    }

    private static func safe(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines)
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return String(cleaned.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
    }
}

private enum ScrapeError: LocalizedError {
    case searchRedirected(URL)
    case notPDF(requested: URL, returned: URL?, contentType: String?)

    var errorDescription: String? {
        switch self {
        case .searchRedirected(let url):
            return "CIA redirected the advanced search to \(url.absoluteString). Open the search in Safari once, then retry."
        case .notPDF(let requested, let returned, let contentType):
            let response = returned?.absoluteString ?? requested.absoluteString
            let type = contentType.map { " (\($0))" } ?? ""
            if requested.host?.lowercased().hasSuffix("jstor.org") == true {
                return "JSTOR returned a webpage instead of a PDF at \(response)\(type). Sign in through the JSTOR window inside sunBear—not Chrome—and click Download on one article there once if JSTOR asks you to accept its download terms."
            }
            if requested.host?.lowercased() == "pmc.ncbi.nlm.nih.gov" {
                return "PMC returned its Preparing to download webpage instead of the PDF at \(response)\(type). Open PubMed inside sunBEAR and use Prepare PDF Downloads once, wait for the PDF to appear, then retry the scrape."
            }
            return "The source returned a webpage instead of a PDF at \(response)\(type), so sunBEAR did not save it as a PDF."
        }
    }
}
