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

                Button("Import Visible Results", systemImage: "square.and.arrow.down") {
                    Task { await importVisibleResults() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)

                Button("Close") { dismiss() }
            }
            .padding(10)

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

        do {
            let pageURL = session.webView.url ?? URL(string: "https://www.cia.gov")!
            let html = try await session.visibleHTML()
            let results = CIASearchResultParser().parse(html: html, baseURL: pageURL)
            guard !results.isEmpty else {
                throw ImportError.noVisibleResults
            }

            let queryName = await session.visibleQueryName()
            var query = CIASearchQuery()
            query.searchTerms = queryName
            query.maximumPages = 1
            query.maximumDocumentRequests = min(100, results.count)

            let job = ScrapeJob(query: query)
            job.status = .running
            modelContext.insert(job)
            var records: [CIADocumentRecord] = []

            for (index, result) in results.prefix(100).enumerated() {
                try Task.checkCancellation()
                progressText = "Importing metadata \(index + 1) of \(min(100, results.count))…"
                if index > 0 {
                    try await Task.sleep(for: .seconds(Double.random(in: 2.5...5.0)))
                }
                let detailHTML = try await session.fetchHTML(from: result.documentURL)
                if let record = CIADocumentParser().parse(
                    html: detailHTML,
                    sourceURL: result.documentURL
                ) {
                    records.append(record)
                }
            }

            for record in records {
                let savedDocument = SavedCIADocument(record: record, job: job)
                modelContext.insert(savedDocument)
                job.documents.append(savedDocument)
            }

            job.pagesCompleted = 1
            job.documentsDiscovered = results.count
            job.documentsParsed = records.count
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
            progressText = "Saved \(records.count) documents and Metadata TSV"
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
