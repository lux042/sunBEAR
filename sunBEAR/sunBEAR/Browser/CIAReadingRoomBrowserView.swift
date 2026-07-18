import Combine
import SwiftData
import SwiftUI
import WebKit

@MainActor
private final class CIAReadingRoomSession: ObservableObject {
    let webView: WKWebView
    private var hasLoaded = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
    }

    func loadIfNeeded() {
        guard !hasLoaded,
              let url = URL(string: "https://www.cia.gov/readingroom/advanced-search-view")
        else { return }
        hasLoaded = true
        webView.load(URLRequest(url: url))
    }

    func visibleHTML() async throws -> String {
        let value = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
        return value as? String ?? ""
    }

    func visibleQueryName() async -> String {
        let script = "document.querySelector('[name=keyword]')?.value || ''"
        let value = try? await webView.evaluateJavaScript(script)
        let query = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return query.isEmpty ? "CIA Browser Import" : query
    }

    func fetchHTML(from url: URL) async throws -> String {
        let script = """
        const response = await fetch(url, { credentials: 'include' });
        if (!response.ok) { throw new Error(`HTTP ${response.status}`); }
        return await response.text();
        """
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: ["url": url.absoluteString],
            in: nil,
            contentWorld: .page
        )
        return value as? String ?? ""
    }
}

private struct CIAWebView: NSViewRepresentable {
    let session: CIAReadingRoomSession

    func makeNSView(context: Context) -> WKWebView {
        session.loadIfNeeded()
        return session.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct CIAReadingRoomBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session = CIAReadingRoomSession()
    @State private var isImporting = false
    @State private var progressText: String?
    @State private var errorMessage: String?
    @State private var importComplete = false
    @State private var pagesToImport = 1

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left") { session.webView.goBack() }
                    .disabled(!session.webView.canGoBack)
                Button("Forward", systemImage: "chevron.right") { session.webView.goForward() }
                    .disabled(!session.webView.canGoForward)
                Button("Reload", systemImage: "arrow.clockwise") { session.webView.reload() }

                Spacer()

                if let progressText {
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $pagesToImport, in: 1...5) {
                    Text("\(pagesToImport) page\(pagesToImport == 1 ? "" : "s")")
                        .monospacedDigit()
                }
                .fixedSize()
                .disabled(isImporting)
                .help("Import the visible page and up to four following pages")

                Button("Import Results", systemImage: "square.and.arrow.down") {
                    Task { await importVisibleResults() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)

                Button("Close") { dismiss() }
            }
            .padding(10)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("Pagination starts on the CIA results page currently visible below. To collect another batch, navigate to the desired starting page, choose 1–5 pages, then click Import Results. Each import is limited to 100 documents.")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            CIAWebView(session: session)
        }
        .frame(minWidth: 900, minHeight: 650)
        .background(Color.sunBearNavy)
        .tint(.sunBearGold)
        .alert("Metadata Saved", isPresented: $importComplete) {
            Button("Done") { dismiss() }
        } message: {
            Text(progressText ?? "The visible CIA results were saved to the Library.")
        }
    }

    @MainActor
    private func importVisibleResults() async {
        isImporting = true
        errorMessage = nil
        progressText = "Reading visible results…"
        await ScrapeNotificationManager.shared.requestAuthorization()

        do {
            let pageURL = session.webView.url ?? URL(string: "https://www.cia.gov")!
            var pageHTML = try await session.visibleHTML()
            var currentPageURL = pageURL
            let firstPage = CIASearchResultParser().parsePage(
                html: pageHTML,
                baseURL: currentPageURL
            )
            guard !firstPage.results.isEmpty else {
                throw ImportError.noVisibleResults
            }

            let queryName = await session.visibleQueryName()
            var query = CIASearchQuery()
            query.searchTerms = queryName
            query.maximumPages = pagesToImport
            query.maximumDocumentRequests = min(100, pagesToImport * 20)

            let job = ScrapeJob(query: query)
            job.status = .running
            modelContext.insert(job)
            try modelContext.save()
            var records: [CIADocumentRecord] = []
            var discoveredURLs = Set<URL>()
            var pagesCompleted = 0
            var documentRequests = 0

            while pagesCompleted < pagesToImport && documentRequests < 100 {
                let page = CIASearchResultParser().parsePage(
                    html: pageHTML,
                    baseURL: currentPageURL
                )
                let newResults = page.results.filter {
                    discoveredURLs.insert($0.documentURL).inserted
                }
                pagesCompleted += 1

                for result in newResults {
                    guard documentRequests < 100 else { break }
                    try Task.checkCancellation()
                    documentRequests += 1
                    job.pagesCompleted = pagesCompleted
                    job.documentsDiscovered = discoveredURLs.count
                    job.completionPercentage = min(
                        99,
                        Int((Double(documentRequests) / Double(max(1, query.maximumDocumentRequests))) * 100)
                    )
                    job.updatedAt = .now
                    try? modelContext.save()
                    progressText = "Page \(pagesCompleted) of \(pagesToImport): metadata \(documentRequests) of up to \(min(100, pagesToImport * 20))…"
                    if documentRequests > 1 {
                        try await Task.sleep(for: .seconds(Double.random(in: 2.5...5.0)))
                    }
                    let detailHTML = try await session.fetchHTML(from: result.documentURL)
                    if let record = CIADocumentParser().parse(
                        html: detailHTML,
                        sourceURL: result.documentURL
                    ) {
                        records.append(record)
                        job.documentsParsed = records.count
                        job.updatedAt = .now
                        try? modelContext.save()
                    }
                }

                guard pagesCompleted < pagesToImport,
                      documentRequests < 100,
                      let nextPageURL = page.nextPageURL
                else { break }

                progressText = "Waiting before page \(pagesCompleted + 1)…"
                try await Task.sleep(for: .seconds(Double.random(in: 8.0...15.0)))
                pageHTML = try await session.fetchHTML(from: nextPageURL)
                currentPageURL = nextPageURL
            }

            for record in records {
                let savedDocument = SavedCIADocument(record: record, job: job)
                modelContext.insert(savedDocument)
                job.documents.append(savedDocument)
            }

            job.pagesCompleted = pagesCompleted
            job.documentsDiscovered = discoveredURLs.count
            job.documentsParsed = records.count
            job.completionPercentage = 100
            job.status = records.isEmpty ? .failed : .completed
            job.updatedAt = .now

            if !records.isEmpty {
                let fileURL = try MetadataTSVExporter().export(
                    records: records,
                    jobID: job.id,
                    displayName: job.displayName
                )
                job.endNoteTSVPath = fileURL.path
            } else {
                job.lastErrorMessage = "The visible results were found, but their metadata pages could not be parsed."
            }

            try modelContext.save()
            progressText = "Saved \(records.count) documents from \(pagesCompleted) page\(pagesCompleted == 1 ? "" : "s") and Metadata TSV"
            ScrapeNotificationManager.shared.notifyCompletion(
                searchName: queryName,
                documentCount: records.count
            )
            importComplete = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isImporting = false
    }
}

private enum ImportError: LocalizedError {
    case noVisibleResults

    var errorDescription: String? {
        "No CIA document results are visible. Submit a search in the page first, then click Import Visible Results."
    }
}
