import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query(sort: \ScrapeSession.startedAt, order: .reverse) private var sessions: [ScrapeSession]
    @State private var scraper = ScrapeService()
    @State private var searchURL = "https://www.cia.gov/readingroom/search/site"
    @State private var downloadFolder: URL?
    @State private var choosingFolder = false
    @State private var showingCIASearch = false
    @State private var shouldDownloadPDFs = true
    @State private var filter = ""
    @State private var sortOrder = [KeyPathComparator(\Item.title)]
    @State private var selection: Item.ID?
    @State private var sessionSelection: ScrapeSession.ID?
    @State private var pendingDelete: ScrapeSession?

    private var selectedSession: ScrapeSession? { sessions.first { $0.id == sessionSelection } }

    private var displayedItems: [Item] {
        let sessionItems = selectedSession?.items ?? []
        let filtered = filter.isEmpty ? sessionItems : sessionItems.filter {
            $0.title.localizedCaseInsensitiveContains(filter) ||
            $0.documentNumber.localizedCaseInsensitiveContains(filter) ||
            $0.collection.localizedCaseInsensitiveContains(filter) ||
            $0.body.localizedCaseInsensitiveContains(filter)
        }
        return filtered.sorted(using: sortOrder)
    }

    private var selectedItem: Item? { items.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            sessionSidebar
                .navigationTitle("sunBEAR")
        } content: {
            library
                .navigationTitle("Library")
                .searchable(text: $filter, prompt: "Title, number, collection, or text")
        } detail: {
            if let item = selectedItem { DocumentDetailView(item: item) }
            else { ContentUnavailableView("Select a document", systemImage: "doc.text.magnifyingglass") }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { downloadFolder = url }
        }
        .sheet(isPresented: $showingCIASearch) {
            CIASearchBrowser { url in
                searchURL = url.absoluteString
                if let folder = downloadFolder {
                    if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: shouldDownloadPDFs, context: modelContext) {
                        sessionSelection = session.id
                    }
                } else {
                    scraper.status = "Search imported—choose a PDF folder, then start the scrape."
                }
            }
        }
        .toolbar { exportToolbar }
        .alert("Delete this scrape from the library?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete from Library", role: .destructive) {
                if let session = pendingDelete { deleteSession(session) }
                pendingDelete = nil
            }
        } message: {
            Text("Its library records will be deleted. Downloaded PDFs and TSV files will remain on disk.")
        }
        .task { createLegacySessionIfNeeded() }
        .frame(minWidth: 1050, minHeight: 650)
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            scrapeControls.padding([.horizontal, .top])
            Divider()
            Text("Scrape sessions").font(.headline).padding(.horizontal)
            List(selection: $sessionSelection) {
                ForEach(sessions) { session in
                    HStack {
                        Image(systemName: "folder")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name).lineLimit(2)
                            Text("\(session.items.count) records · \(session.pagesScraped) page\(session.pagesScraped == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("Download TSV File") { export(session: session, endNote: false) }
                        Button("Download EndNote File") { export(session: session, endNote: true) }
                        if !session.folderPath.isEmpty {
                            Button("Show Session Folder in Finder") { showInFinder(URL(fileURLWithPath: session.folderPath)) }
                        }
                        Divider()
                        Button("Delete from Library", role: .destructive) { pendingDelete = session }
                    }
                }
            }
        }
    }

    private var scrapeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New scrape").font(.headline)
            Button { showingCIASearch = true } label: {
                Label("Open CIA Search", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            TextField("CIA search-results URL", text: $searchURL, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Text("Search inside sunBEAR and import the results page, or paste a results URL above.")
                .font(.caption).foregroundStyle(.secondary)
            Button { choosingFolder = true } label: {
                Label(downloadFolder?.lastPathComponent ?? "Choose PDF folder", systemImage: "folder")
            }
            .help(downloadFolder?.path ?? "Every PDF linked by every result will be downloaded here")
            Toggle("Download PDFs", isOn: $shouldDownloadPDFs)
                .help("Turn off to collect metadata and abstracts without downloading PDF files")
            if scraper.isRunning {
                ProgressView(value: scraper.total == 0 ? nil : Double(scraper.completed), total: Double(max(scraper.total, 1)))
                Button("Stop", role: .destructive) { scraper.cancel() }
            } else {
                Button(shouldDownloadPDFs ? "Scrape and download PDFs" : "Scrape metadata only") { startScrape() }
                    .disabled(downloadFolder == nil || URL(string: searchURL) == nil)
            }
            Text(scraper.status).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var library: some View {
        Group {
            if selectedSession == nil {
                ContentUnavailableView("Select a scrape session", systemImage: "folder")
            } else {
                Table(displayedItems, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \Item.title) { Text($0.title).lineLimit(2) }.width(min: 240, ideal: 360)
            TableColumn("Collection", value: \Item.collection) { Text($0.collection) }.width(min: 120, ideal: 180)
            TableColumn("Document No.", value: \Item.documentNumber) { Text($0.documentNumber) }.width(min: 130, ideal: 180)
            TableColumn("Date", value: \Item.publicationDate) { Text($0.publicationDate) }.width(min: 90, ideal: 120)
            TableColumn("Pages", value: \Item.pageCount) { Text($0.pageCount == 0 ? "—" : String($0.pageCount)) }.width(55)
            TableColumn("PDFs", value: \Item.localPDFPaths.count) { item in
                if !item.downloadError.isEmpty { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).help(item.downloadError) }
                else { Text("\(item.localPDFPaths.count)/\(item.pdfURLs.count)") }
            }.width(55)
                }
            }
        }
    }

    @ToolbarContentBuilder private var exportToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { if let session = selectedSession { export(session: session, endNote: false) } } label: { Label("Export TSV", systemImage: "square.and.arrow.up") }
                .disabled(selectedSession?.items.isEmpty != false)
            Button { if let session = selectedSession { export(session: session, endNote: true) } } label: { Label("Export to EndNote", systemImage: "books.vertical") }
                .disabled(selectedSession?.items.isEmpty != false)
                .help("Creates an EndNote-ready TSV whose filename begins with *CIA")
        }
    }

    private func startScrape() {
        guard let url = URL(string: searchURL), let folder = downloadFolder else { return }
        if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: shouldDownloadPDFs, context: modelContext) {
            sessionSelection = session.id
        }
    }

    private func export(session: ScrapeSession, endNote: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tabSeparatedText]
        panel.nameFieldStringValue = endNote ? "*CIA \(session.name).tsv" : "\(session.name).tsv"
        if !session.folderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: session.folderPath) }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let sessionItems = session.items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let value = endNote ? ExportService.endNoteTSV(items: sessionItems) : ExportService.preservationTSV(items: sessionItems)
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
            showInFinder(url)
            scraper.status = "Exported \(url.lastPathComponent) and revealed it in Finder."
        }
        catch { scraper.status = "Export failed: \(error.localizedDescription)" }
    }

    private func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteSession(_ session: ScrapeSession) {
        if sessionSelection == session.id { sessionSelection = nil; selection = nil }
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func createLegacySessionIfNeeded() {
        let orphaned = items.filter { $0.session == nil }
        guard !orphaned.isEmpty else { return }
        let legacy = ScrapeSession(name: "Earlier imported records", searchURL: "", startedAt: orphaned.map(\.scrapedAt).min() ?? .now, isComplete: true)
        modelContext.insert(legacy)
        for item in orphaned { item.session = legacy }
        try? modelContext.save()
        if sessionSelection == nil { sessionSelection = legacy.id }
    }
}

private struct DocumentDetailView: View {
    let item: Item

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.title2).textSelection(.enabled)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    row("Document number", item.documentNumber)
                    row("Collection", item.collection)
                    row("Document type", item.documentType)
                    row("Publication date", item.publicationDate)
                    row("Pages", item.pageCount == 0 ? "" : String(item.pageCount))
                    row("Classification", item.originalClassification)
                    row("Release decision", item.releaseDecision)
                }
                Divider()
                Link("Open CIA record", destination: URL(string: item.recordURL)!)
                ForEach(Array(item.localPDFPaths.enumerated()), id: \.offset) { index, path in
                    Link("Open downloaded PDF \(index + 1)", destination: URL(fileURLWithPath: path))
                }
                if !item.downloadError.isEmpty { Text(item.downloadError).foregroundStyle(.orange) }
                Text("Abstract").font(.headline)
                Text(item.body.isEmpty ? "No body text was found." : item.body).textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow { Text(label).foregroundStyle(.secondary); Text(value).textSelection(.enabled) }
        }
    }
}

#Preview {
    ContentView().modelContainer(for: [Item.self, ScrapeSession.self], inMemory: true)
}
