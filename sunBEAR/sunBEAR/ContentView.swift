import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

private enum FileImporterMode {
    case saveLocation
    case archivalPDFs
}

struct ContentView: View {
    private let forestGreen = Color(red: 30 / 255, green: 66 / 255, blue: 53 / 255)
    private let actionGreen = Color(red: 38 / 255, green: 100 / 255, blue: 70 / 255)
    private let warmBackground = Color(red: 248 / 255, green: 248 / 255, blue: 244 / 255)
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query(sort: \ScrapeSession.startedAt, order: .reverse) private var sessions: [ScrapeSession]
    @Query(sort: \LibraryCollection.name) private var collections: [LibraryCollection]
    @State private var scraper = ScrapeService()
    @State private var browserSession = BrowserSession()
    @State private var selectedSource = ScrapeSource.cia
    @State private var searchURL = "https://www.cia.gov/readingroom/search/site"
    @State private var downloadFolder: URL?
    @State private var fileImporterMode = FileImporterMode.archivalPDFs
    @State private var fileImporterPresented = false
    @State private var pendingArchivalPDFURLs: [URL] = []
    @State private var showingSearchBrowser = false
    @State private var browserURLOverride: URL?
    @State private var shouldDownloadPDFs = true
    @State private var shouldSaveArticlePages = true
    @State private var requestedPageCount = 1
    @State private var filter = ""
    @State private var sessionFilter = ""
    @State private var sessionSort = SessionSort.newest
    @State private var sortOrder = [KeyPathComparator(\Item.title)]
    @State private var selection: Item.ID?
    @State private var sessionSelections = Set<ScrapeSession.ID>()
    @State private var pendingDeleteSessions: [ScrapeSession] = []
    @State private var renamingSession: ScrapeSession?
    @State private var renameText = ""
    @State private var expandedCollections = Set<PersistentIdentifier>()
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""
    @State private var renamingCollection: LibraryCollection?
    @State private var collectionName = ""
    @State private var pendingCollectionDelete: LibraryCollection?
    @State private var deleteCollectionSessions = false
    @State private var endNoteAlert: String?

    private var selectedSessions: [ScrapeSession] { sessions.filter { sessionSelections.contains($0.id) } }
    private var selectedSession: ScrapeSession? { selectedSessions.first }

    private var displayedSessions: [ScrapeSession] {
        let filtered = sessionFilter.isEmpty ? sessions : sessions.filter {
            $0.name.localizedCaseInsensitiveContains(sessionFilter)
        }
        switch sessionSort {
        case .newest: return filtered.sorted { $0.startedAt > $1.startedAt }
        case .oldest: return filtered.sorted { $0.startedAt < $1.startedAt }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .records: return filtered.sorted { $0.items.count > $1.items.count }
        }
    }

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
        VStack(spacing: 0) {
            brandHeader
            scrapeControls
            statusBar
            NavigationSplitView {
                sessionSidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 330)
            } content: {
                library
                    .navigationSplitViewColumnWidth(min: 480, ideal: 690)
            } detail: {
                if let item = selectedItem { DocumentDetailView(item: item, securityScopedRoot: downloadFolder) }
                else { ContentUnavailableView("Select a record", systemImage: "doc.text.magnifyingglass") }
            }
            .tint(forestGreen)
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: fileImporterMode == .archivalPDFs ? [.pdf] : [.folder],
            allowsMultipleSelection: fileImporterMode == .archivalPDFs
        ) { result in
            let completedMode = fileImporterMode
            switch (completedMode, result) {
            case (.saveLocation, .success(let urls)):
                guard let url = urls.first else { return }
                downloadFolder = url
                if !pendingArchivalPDFURLs.isEmpty {
                    let pdfs = pendingArchivalPDFURLs
                    pendingArchivalPDFURLs = []
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        importArchivalPDFs(pdfs)
                    }
                }
            case (.archivalPDFs, .success(let urls)):
                if downloadFolder == nil {
                    pendingArchivalPDFURLs = urls
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        fileImporterMode = .saveLocation
                        fileImporterPresented = true
                    }
                } else {
                    importArchivalPDFs(urls)
                }
            case (_, .failure(let error)):
                pendingArchivalPDFURLs = []
                scraper.status = "File selection failed: \(error.localizedDescription)"
            default:
                pendingArchivalPDFURLs = []
            }
        }
        .sheet(isPresented: $showingSearchBrowser) {
            SearchBrowser(webView: browserSession.webView, source: selectedSource, initialURL: browserURLOverride ?? browserInitialURL, pageCount: requestedPageCount) { url, renderedHTML in
                searchURL = url.absoluteString
                if let folder = downloadFolder {
                    if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: selectedSource != .nyt && shouldDownloadPDFs, saveArticlePages: selectedSource == .nyt && shouldSaveArticlePages, pageLimit: requestedPageCount, renderedSearchHTML: renderedHTML, authenticatedWebView: [.nyt, .jstor, .ebsco].contains(selectedSource) ? browserSession.webView : nil, context: modelContext) {
                        sessionSelections = [session.id]
                    }
                } else {
                    scraper.status = "Search imported—choose a PDF folder, then start the scrape."
                }
            }
        }
        .onChange(of: showingSearchBrowser) { _, showing in
            if !showing { browserURLOverride = nil }
        }
        .preferredColorScheme(.light)
        .alert(pendingDeleteSessions.count == 1 ? "Delete this scrape from the library?" : "Delete \(pendingDeleteSessions.count) scrapes from the library?", isPresented: Binding(get: { !pendingDeleteSessions.isEmpty }, set: { if !$0 { pendingDeleteSessions = [] } })) {
            Button("Cancel", role: .cancel) { pendingDeleteSessions = [] }
            Button("Delete from Library", role: .destructive) {
                deleteSessions(pendingDeleteSessions)
                pendingDeleteSessions = []
            }
        } message: {
            Text("Its library records will be deleted. Downloaded PDFs and TSV files will remain on disk.")
        }
        .alert("Rename scrape session", isPresented: Binding(get: { renamingSession != nil }, set: { if !$0 { renamingSession = nil } })) {
            TextField("Session name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingSession = nil }
            Button("Rename") { finishRenamingSession() }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("This changes the name shown in the library and used for future exports. It does not rename the existing folder on disk.")
        }
        .alert("New collection", isPresented: $showingNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { newCollectionName = "" }
            Button("Create") { createCollection() }
                .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Collections group related scrape sessions like folders in Finder.")
        }
        .alert("Rename collection", isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } })) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) { renamingCollection = nil }
            Button("Rename") { finishRenamingCollection() }
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(deleteCollectionSessions ? "Delete collection and its contents?" : "Delete this collection?", isPresented: Binding(get: { pendingCollectionDelete != nil }, set: { if !$0 { pendingCollectionDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingCollectionDelete = nil }
            Button(deleteCollectionSessions ? "Delete Collection and Sessions" : "Delete Collection", role: .destructive) { deletePendingCollection() }
        } message: {
            Text(deleteCollectionSessions ? "The collection and all scrape sessions inside it will be removed from the library. Downloaded files will remain on disk." : "Its scrape sessions will be preserved and moved to Unfiled.")
        }
        .alert("EndNote Export", isPresented: Binding(get: { endNoteAlert != nil }, set: { if !$0 { endNoteAlert = nil } })) {
            Button("OK") { endNoteAlert = nil }
        } message: {
            Text(endNoteAlert ?? "")
        }
        .task { createLegacySessionIfNeeded() }
        .frame(minWidth: 1050, minHeight: 720)
    }

    private var brandHeader: some View {
        HStack {
            Text("sunBEAR")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
        .background(forestGreen)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if scraper.isRunning {
                ProgressView(value: scraper.total == 0 ? nil : Double(scraper.completed), total: Double(max(scraper.total, 1)))
                    .frame(width: 150)
            }
            Text(scraper.status.isEmpty ? "Ready — choose a source and browse, or paste a search-results URL." : scraper.status)
                .font(.caption)
                .foregroundStyle(Color(red: 50 / 255, green: 70 / 255, blue: 59 / 255))
                .lineLimit(2)
            Spacer()
            if scraper.isRunning, scraper.total > 0 {
                Text("\(scraper.completed) of \(scraper.total) processed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(Color(red: 236 / 255, green: 239 / 255, blue: 229 / 255))
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIBRARY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { beginCreatingCollection() } label: {
                    Label("New Collection", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Create a collection")
                Menu {
                    Picker("Sort sessions", selection: $sessionSort) {
                        ForEach(SessionSort.allCases) { option in
                            Label(option.title, systemImage: option.icon).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                        .labelStyle(.iconOnly)
                }
                .help("Sort library folders")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            TextField("Find a saved search", text: $sessionFilter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
            List(selection: $sessionSelections) {
                ForEach(collections) { collection in
                    DisclosureGroup(isExpanded: expansionBinding(for: collection)) {
                        let collectionSessions = displayedSessions.filter { $0.libraryCollection?.persistentModelID == collection.persistentModelID }
                        if collectionSessions.isEmpty {
                            Text("No sessions").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(collectionSessions) { session in sessionRow(session) }
                        }
                    } label: {
                        Label("\(collection.name) (\(collection.sessions.count))", systemImage: "folder.fill")
                            .contextMenu {
                                Button("Select Contents") { sessionSelections = Set(collection.sessions.map(\.id)) }
                                Button("Download All TSV Files") { exportSessions(collection.sessions) }
                                Button("Send Collection to EndNote") { sendToEndNote(collection.sessions) }
                                Divider()
                                Button("Rename Collection") { beginRenamingCollection(collection) }
                                Button("Delete Collection Only", role: .destructive) { prepareCollectionDeletion(collection, includingSessions: false) }
                                Button("Delete Collection and Contents", role: .destructive) { prepareCollectionDeletion(collection, includingSessions: true) }
                            }
                    }
                }
                let unfiled = displayedSessions.filter { $0.libraryCollection == nil }
                if !unfiled.isEmpty {
                    Section("Unfiled") {
                        ForEach(unfiled) { session in sessionRow(session) }
                    }
                }
                if collections.isEmpty && unfiled.isEmpty {
                    Text(sessionFilter.isEmpty ? "No scrape sessions yet" : "No matching sessions")
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(warmBackground)
            if !selectedSessions.isEmpty, let session = selectedSession {
                HStack {
                    Text("\(selectedSessions.count) selected").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        if selectedSessions.count == 1 {
                            Button("Rename Session") { beginRenamingSession(session) }
                        }
                        moveMenu(for: selectedSessions)
                        Divider()
                        Button(selectedSessions.count == 1 ? "Download TSV File" : "Download TSV Files") { exportSessions(selectedSessions) }
                        Button(selectedSessions.count == 1 ? "Send to EndNote" : "Send Selected to EndNote") { sendToEndNote(selectedSessions) }
                        if selectedSessions.count == 1, !session.folderPath.isEmpty {
                            Button("Show Session Folder in Finder") { showInFinder(URL(fileURLWithPath: session.folderPath)) }
                        }
                        Divider()
                        Button("Delete Selected from Library", role: .destructive) { pendingDeleteSessions = selectedSessions }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
                .labelStyle(.iconOnly)
                .padding([.horizontal, .bottom])
            }
        }
        .background(warmBackground)
    }

    private func sessionRow(_ session: ScrapeSession) -> some View {
        HStack {
            Image(systemName: session.isComplete ? "doc.text.fill" : "doc.badge.gearshape")
                .foregroundStyle(session.isComplete ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name).lineLimit(2)
                Text("\(session.items.count) records · \(session.pagesScraped) page\(session.pagesScraped == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(session.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .tag(session.id)
        .contextMenu {
            let targets = sessionSelections.contains(session.id) ? selectedSessions : [session]
            Button("Rename Session") { beginRenamingSession(session) }
                .disabled(targets.count > 1)
            moveMenu(for: targets)
            Divider()
            Button(targets.count == 1 ? "Download TSV File" : "Download TSV Files") { exportSessions(targets) }
            Button(targets.count == 1 ? "Send to EndNote" : "Send Selected to EndNote") { sendToEndNote(targets) }
            if targets.count == 1, !session.folderPath.isEmpty {
                Button("Show Session Folder in Finder") { showInFinder(URL(fileURLWithPath: session.folderPath)) }
            }
            Divider()
            Button(targets.count == 1 ? "Delete from Library" : "Delete Selected from Library", role: .destructive) { pendingDeleteSessions = targets }
        }
    }

    private func moveMenu(for targets: [ScrapeSession]) -> some View {
        Menu(targets.count == 1 ? "Move to Collection" : "Move Selected to Collection") {
            Button {
                move(targets, to: nil)
            } label: {
                if targets.allSatisfy({ $0.libraryCollection == nil }) { Label("Unfiled", systemImage: "checkmark") }
                else { Text("Unfiled") }
            }
            Divider()
            ForEach(collections) { collection in
                Button {
                    move(targets, to: collection)
                } label: {
                    if targets.allSatisfy({ $0.libraryCollection?.persistentModelID == collection.persistentModelID }) {
                        Label(collection.name, systemImage: "checkmark")
                    } else {
                        Text(collection.name)
                    }
                }
            }
            Divider()
            Button("New Collection…") {
                beginCreatingCollection()
            }
        }
    }

    private var scrapeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Source", selection: $selectedSource) {
                    ForEach(ScrapeSource.allCases) { source in Text(source.title).tag(source) }
                }
                .labelsHidden()
                .frame(width: 175)
                .onChange(of: selectedSource) { _, source in searchURL = source.defaultSearchURL }

                TextField(selectedSource.searchURLPrompt, text: $searchURL)
                    .textFieldStyle(.roundedBorder)

                Button(browserButtonTitle) {
                    openSourceBrowser(at: browserInitialURL ?? selectedSource.homeURL)
                }

                Button("Import records") { startScrape() }
                    .buttonStyle(.borderedProminent)
                    .tint(actionGreen)
                    .disabled([.nyt, .jstor, .ebsco].contains(selectedSource) || scraper.isRunning || downloadFolder == nil || URL(string: searchURL) == nil)
                    .help([.nyt, .jstor, .ebsco].contains(selectedSource) ? "Use the source browser so sunBEAR imports with the same signed-in session." : "Import the pasted search-results URL")
                Button("Import archival PDF…") { beginArchivalPDFImport() }
                    .disabled(scraper.isRunning)
                    .help(downloadFolder == nil ? "Choose a save location, then select one or more archival PDFs" : "Extract a draft archival record and attach the original PDF")
            }
            HStack(spacing: 14) {
                Stepper("Search pages: \(requestedPageCount)", value: $requestedPageCount, in: 1...ScrapeService.maximumSearchPages)
                    .fixedSize()
                if selectedSource != .nyt {
                    Toggle("Download PDFs", isOn: $shouldDownloadPDFs)
                        .fixedSize()
                }
                Button {
                    fileImporterMode = .saveLocation
                    fileImporterPresented = true
                } label: {
                    Label(downloadFolder?.lastPathComponent ?? "Save location…", systemImage: "folder")
                }
                .help(downloadFolder?.path ?? "Choose where downloaded source files will be saved")
                if selectedSource == .nyt {
                    Toggle("Save readable articles", isOn: $shouldSaveArticlePages)
                        .fixedSize()
                        .help("Save the readable article text available to your signed-in NYT account as offline HTML")
                    Menu("NYT options") {
                        Button("Open NYT Search") { openSourceBrowser(at: ScrapeSource.nyt.homeURL) }
                        Button("Open TimesMachine") { openSourceBrowser(at: URL(string: "https://timesmachine.nytimes.com/browser")) }
                    }
                }
                Spacer()
                if scraper.isRunning {
                    Button("Stop task", role: .destructive) { scraper.cancel() }
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var browserInitialURL: URL? {
        guard let url = URL(string: searchURL), selectedSource.canImport(url) else { return nil }
        return url
    }

    private var browserButtonTitle: String {
        switch selectedSource {
        case .nyt: "Search New York Times"
        case .jstor: "Search JSTOR"
        case .eric: "Search ERIC"
        case .ebsco: "Search EBSCO"
        default: "Browse source"
        }
    }

    private func openSourceBrowser(at url: URL?) {
        browserURLOverride = url
        showingSearchBrowser = true
    }

    private var library: some View {
        VStack(spacing: 0) {
            if selectedSession == nil {
                ContentUnavailableView("Select a scrape session", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved records").font(.title3.bold()).lineLimit(1)
                        Text("\(displayedItems.count) of \(selectedSession?.items.count ?? 0) records")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Search saved records", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                    Menu("Export…") {
                        Button("Spreadsheet (TSV)") { exportSessions(selectedSessions) }
                        Button("Send to EndNote") { sendToEndNote(selectedSessions) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(red: 236 / 255, green: 242 / 255, blue: 238 / 255))
                Divider()
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
        .background(.white)
    }

    private func startScrape() {
        guard let url = URL(string: searchURL), let folder = downloadFolder else { return }
        if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: shouldDownloadPDFs, saveArticlePages: selectedSource == .nyt && shouldSaveArticlePages, pageLimit: requestedPageCount, context: modelContext) {
            sessionSelections = [session.id]
        }
    }

    private func importArchivalPDFs(_ urls: [URL]) {
        guard let destination = downloadFolder, !urls.isEmpty else {
            scraper.status = "Choose a save location before importing archival PDFs."
            return
        }
        let rootAccess = destination.startAccessingSecurityScopedResource()
        defer { if rootAccess { destination.stopAccessingSecurityScopedResource() } }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let sessionName = "Archival PDFs - \(formatter.string(from: .now))"
        let sessionFolder = destination.appendingPathComponent(sessionName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sessionFolder, withIntermediateDirectories: true)
            let session = ScrapeSession(name: sessionName, searchURL: "local-pdf-import", folderPath: sessionFolder.path, startedAt: .now, pagesScraped: urls.count, isComplete: true)
            modelContext.insert(session)
            var imported = 0
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                var target = sessionFolder.appendingPathComponent(url.lastPathComponent)
                var suffix = 2
                while FileManager.default.fileExists(atPath: target.path) {
                    target = sessionFolder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(suffix).pdf")
                    suffix += 1
                }
                try FileManager.default.copyItem(at: url, to: target)
                let extracted = try ArchivalPDFExtractor.extract(from: target)
                let item = Item(title: extracted.title, documentType: "Archival PDF bundle", collection: "Local archival documents", documentNumber: extracted.documentNumber, releaseDecision: "Declassified", originalClassification: extracted.originalClassification, pageCount: extracted.pageCount, documentCreationDate: extracted.publicationDate, publicationDate: extracted.publicationDate, contentType: "Department of State archival record", caseNumber: extracted.caseNumber, recordURL: target.absoluteString, body: extracted.abstract, keywords: extracted.keywords, localPDFPaths: [target.path], session: session)
                modelContext.insert(item)
                imported += 1
            }
            sessionSelections = [session.id]
            scraper.status = "Imported \(imported) archival PDF bundle\(imported == 1 ? "" : "s"). Review the draft metadata before sending to EndNote."
        } catch {
            scraper.status = "PDF import failed: \(error.localizedDescription)"
        }
    }

    private func beginArchivalPDFImport() {
        fileImporterMode = .archivalPDFs
        fileImporterPresented = true
    }

    private func exportSessions(_ sessions: [ScrapeSession]) {
        guard !sessions.isEmpty else { return }
        if sessions.count == 1, let session = sessions.first {
            export(session: session)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Export Folder"
        panel.message = "Choose one folder for \(sessions.count) TSV exports."
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        var exported = 0
        for session in sessions {
            let filename = safeExportFilename("\(session.name).tsv")
            let url = availableExportURL(folder.appendingPathComponent(filename))
            let sortedItems = session.items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            let value = ExportService.preservationTSV(items: sortedItems)
            if (try? value.write(to: url, atomically: true, encoding: .utf8)) != nil { exported += 1 }
        }
        showInFinder(folder)
        scraper.status = "Exported \(exported) of \(sessions.count) files to \(folder.lastPathComponent)."
    }

    private func export(session: ScrapeSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tabSeparatedText]
        panel.nameFieldStringValue = "\(session.name).tsv"
        if !session.folderPath.isEmpty { panel.directoryURL = URL(fileURLWithPath: session.folderPath) }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let sessionItems = session.items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let value = ExportService.preservationTSV(items: sessionItems)
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

    private func sendToEndNote(_ sessions: [ScrapeSession]) {
        guard !sessions.isEmpty else { return }
        let sortedSessions = sessions.sorted { $0.startedAt < $1.startedAt }
        let combinedItems = sortedSessions.flatMap { $0.items }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let name = sessions.count == 1 ? sessions[0].name : "\(sessions.count) sunBEAR sessions"
        Task { @MainActor in
            do {
                try await EndNoteService.send(items: combinedItems, sessionName: name)
                scraper.status = "Sent \(combinedItems.count) records to EndNote. Choose the destination library in EndNote if prompted."
            } catch {
                endNoteAlert = error.localizedDescription
                scraper.status = "EndNote export failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteSessions(_ sessions: [ScrapeSession]) {
        let ids = Set(sessions.map(\.id))
        sessionSelections.subtract(ids)
        if selectedSession == nil { selection = nil }
        for session in sessions { modelContext.delete(session) }
        try? modelContext.save()
    }

    private func safeExportFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?\"<>|").union(.newlines)
        let cleaned = value.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "sunBEAR export.tsv" : String(cleaned.prefix(180))
    }

    private func availableExportURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base)-\(number)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func beginRenamingSession(_ session: ScrapeSession) {
        renameText = session.name
        renamingSession = session
    }

    private func finishRenamingSession() {
        guard let session = renamingSession else { return }
        let value = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        session.name = value
        try? modelContext.save()
        renamingSession = nil
    }

    private func expansionBinding(for collection: LibraryCollection) -> Binding<Bool> {
        Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { expanded in
                if expanded { expandedCollections.insert(collection.persistentModelID) }
                else { expandedCollections.remove(collection.persistentModelID) }
            }
        )
    }

    private func beginCreatingCollection() {
        newCollectionName = ""
        showingNewCollection = true
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let collection = LibraryCollection(name: name)
        modelContext.insert(collection)
        try? modelContext.save()
        expandedCollections.insert(collection.persistentModelID)
        newCollectionName = ""
    }

    private func beginRenamingCollection(_ collection: LibraryCollection) {
        collectionName = collection.name
        renamingCollection = collection
    }

    private func finishRenamingCollection() {
        guard let collection = renamingCollection else { return }
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        collection.name = name
        try? modelContext.save()
        renamingCollection = nil
    }

    private func move(_ sessions: [ScrapeSession], to collection: LibraryCollection?) {
        for session in sessions { session.libraryCollection = collection }
        if let collection { expandedCollections.insert(collection.persistentModelID) }
        try? modelContext.save()
    }

    private func deletePendingCollection() {
        guard let collection = pendingCollectionDelete else { return }
        let contents = Array(collection.sessions)
        if deleteCollectionSessions {
            deleteSessions(contents)
        } else {
            for session in contents { session.libraryCollection = nil }
        }
        expandedCollections.remove(collection.persistentModelID)
        modelContext.delete(collection)
        try? modelContext.save()
        pendingCollectionDelete = nil
        deleteCollectionSessions = false
    }

    private func prepareCollectionDeletion(_ collection: LibraryCollection, includingSessions: Bool) {
        deleteCollectionSessions = includingSessions
        pendingCollectionDelete = collection
    }

    private func createLegacySessionIfNeeded() {
        let orphaned = items.filter { $0.session == nil }
        guard !orphaned.isEmpty else { return }
        let legacy = ScrapeSession(name: "Earlier imported records", searchURL: "", startedAt: orphaned.map(\.scrapedAt).min() ?? .now, isComplete: true)
        modelContext.insert(legacy)
        for item in orphaned { item.session = legacy }
        try? modelContext.save()
        if sessionSelections.isEmpty { sessionSelections = [legacy.id] }
    }
}

private enum SessionSort: String, CaseIterable, Identifiable {
    case newest, oldest, name, records

    var id: Self { self }
    var title: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .name: "Name"
        case .records: "Most records"
        }
    }
    var icon: String {
        switch self {
        case .newest: "calendar.badge.clock"
        case .oldest: "calendar"
        case .name: "textformat"
        case .records: "doc.on.doc"
        }
    }
}

private struct DocumentDetailView: View {
    @Bindable var item: Item
    let securityScopedRoot: URL?
    @State private var openError = ""

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
                if isArchivalPDF {
                    GroupBox("Review extracted metadata") {
                        VStack(alignment: .leading, spacing: 10) {
                            editableField("Title", text: $item.title)
                            editableField("Document numbers", text: $item.documentNumber)
                            editableField("Document type", text: $item.documentType)
                            editableField("Collection", text: $item.collection)
                            editableField("Creation date", text: $item.documentCreationDate)
                            editableField("Release date", text: $item.documentReleaseDate)
                            editableField("Publication date", text: $item.publicationDate)
                            editableField("Classification", text: $item.originalClassification)
                            editableField("Release decision", text: $item.releaseDecision)
                            editableField("Sequence number", text: $item.sequenceNumber)
                            editableField("Content type", text: $item.contentType)
                            editableField("Case number", text: $item.caseNumber)
                            editableField("Keywords", text: $item.keywords)
                            Text("Draft abstract / description").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $item.body)
                                .font(.body)
                                .frame(minHeight: 110)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                            Text("These fields are drafts generated from OCR text. Review them before exporting to EndNote.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                    }
                }
                Divider()
                Button("Open \(sourceTitle) record") { openWebRecord() }
                    .buttonStyle(.link)
                if isEBSCOBook {
                    Button("Choose book download options") { openWebRecord() }
                        .buttonStyle(.link)
                        .help("Open EBSCO to choose a permitted full-book or chapter download")
                }
                ForEach(Array(item.externalURLs.enumerated()), id: \.offset) { index, value in
                    Button(externalLinkTitle(value, index: index)) { openExternalLink(value) }
                        .buttonStyle(.link)
                }
                ForEach(Array(item.localPDFPaths.enumerated()), id: \.offset) { index, path in
                    Button("Open downloaded PDF \(index + 1)") { openLocalFile(path) }
                        .buttonStyle(.link)
                }
                if !item.localArticlePath.isEmpty, sourceTitle == ScrapeSource.ebsco.title {
                    Button(savedFullTextTitle) { openLocalFile(item.localArticlePath) }
                        .buttonStyle(.link)
                }
                if !openError.isEmpty { Text(openError).foregroundStyle(.orange) }
                if !item.downloadError.isEmpty { Text(item.downloadError).foregroundStyle(.orange) }
                if !item.articlePageError.isEmpty { Text("Article page: \(item.articlePageError)").foregroundStyle(.orange) }
                Text("Abstract").font(.headline)
                Text(item.body.isEmpty ? "No body text was found." : item.body).textSelection(.enabled)
                if !item.keywords.isEmpty {
                    Text("Keywords").font(.headline)
                    Text(item.keywords).textSelection(.enabled)
                }
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

    private func editableField(_ label: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 125, alignment: .leading)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var isArchivalPDF: Bool {
        item.contentType == "Department of State archival record" || item.documentType == "Archival PDF bundle"
    }

    private var sourceTitle: String {
        guard let url = URL(string: item.recordURL) else { return "source" }
        return ScrapeSource.source(for: url)?.title ?? "source"
    }

    private var isEBSCOBook: Bool {
        sourceTitle == ScrapeSource.ebsco.title && (
            item.documentType.localizedCaseInsensitiveContains("ebook") ||
            item.documentType.localizedCaseInsensitiveContains("book") ||
            item.collection.localizedCaseInsensitiveContains("ebook")
        )
    }

    private var savedFullTextTitle: String {
        switch URL(fileURLWithPath: item.localArticlePath).pathExtension.lowercased() {
        case "epub": "Open downloaded EPUB eBook"
        case "html", "htm": "Open downloaded HTML full text"
        default: "Open downloaded full text"
        }
    }

    private func openWebRecord() {
        guard let url = URL(string: item.recordURL), NSWorkspace.shared.open(url) else {
            openError = "The source record could not be opened."
            return
        }
        openError = ""
    }

    private func externalLinkTitle(_ value: String, index: Int) -> String {
        guard let host = URL(string: value)?.host?.replacingOccurrences(of: "www.", with: "") else {
            return "Open external resource \(index + 1)"
        }
        return host == "doi.org" ? "Open DOI" : "Open full text at \(host)"
    }

    private func openExternalLink(_ value: String) {
        guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
            openError = "The external resource could not be opened."
            return
        }
        openError = ""
    }

    private func openLocalFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let hasAccess = securityScopedRoot?.startAccessingSecurityScopedResource() ?? false
        defer { if hasAccess { securityScopedRoot?.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: path) else {
            openError = "The downloaded file is no longer at \(path)."
            return
        }
        guard NSWorkspace.shared.open(url) else {
            openError = "macOS could not open \(url.lastPathComponent)."
            return
        }
        openError = ""
    }
}

#Preview {
    ContentView().modelContainer(for: [Item.self, ScrapeSession.self, LibraryCollection.self], inMemory: true)
}
