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
                    if current.path.contains("advanced-search"), !page.finalURL.path.contains("advanced-search") {
                        throw ScrapeError.searchRedirected(page.finalURL)
                    }
                    documentURLs.append(contentsOf: CIAHTMLParser.resultLinks(in: html, baseURL: page.finalURL))
                    documentURLs = Array(Set(documentURLs)).sorted { $0.absoluteString < $1.absoluteString }
                    pageURL = CIAHTMLParser.nextPage(in: html, baseURL: page.finalURL)
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(350))
                }

                total = documentURLs.count
                for (index, url) in documentURLs.enumerated() {
                    status = "Scraping \(index + 1) of \(total)…"
                    let html = try await fetchHTML(url).html
                    let scraped = CIAHTMLParser.document(from: html, url: url)
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
        for (index, url) in urls.enumerated() {
            let (temporary, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
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
        let searchName = values.isEmpty ? "CIA Search" : values.joined(separator: " - ")

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

    var errorDescription: String? {
        switch self {
        case .searchRedirected(let url):
            "CIA redirected the advanced search to \(url.absoluteString). Open the search in Safari once, then retry."
        }
    }
}
