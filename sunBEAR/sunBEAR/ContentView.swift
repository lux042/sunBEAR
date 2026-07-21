import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @Query(sort: \ScrapeSession.startedAt, order: .reverse) private var sessions: [ScrapeSession]
    @Query(sort: \LibraryCollection.name) private var collections: [LibraryCollection]
    @State private var scraper = ScrapeService()
    @State private var searchURL = "https://www.cia.gov/readingroom/search/site"
    @State private var downloadFolder: URL?
    @State private var choosingFolder = false
    @State private var showingCIASearch = false
    @State private var shouldDownloadPDFs = true
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
                    if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: shouldDownloadPDFs, pageLimit: requestedPageCount, context: modelContext) {
                        sessionSelections = [session.id]
                    }
                } else {
                    scraper.status = "Search imported—choose a PDF folder, then start the scrape."
                }
            }
        }
        .toolbar { exportToolbar }
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
        .frame(minWidth: 1050, minHeight: 650)
    }

    private var sessionSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            scrapeControls.padding([.horizontal, .top])
            Divider()
            HStack {
                Text("Library folders").font(.headline)
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
            .padding(.horizontal)
            TextField("Find a scrape session", text: $sessionFilter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
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
            Stepper("Search pages: \(requestedPageCount)", value: $requestedPageCount, in: 1...ScrapeService.maximumSearchPages)
                .help("Choose how many CIA search-result pages to scrape, up to 10")
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
        VStack(spacing: 0) {
            if selectedSession == nil {
                ContentUnavailableView("Select a scrape session", systemImage: "folder")
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedSession?.name ?? "").font(.headline).lineLimit(1)
                        Text("\(displayedItems.count) of \(selectedSession?.items.count ?? 0) records")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !filter.isEmpty { Button("Clear Search") { filter = "" } }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
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
    }

    @ToolbarContentBuilder private var exportToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { exportSessions(selectedSessions) } label: { Label("Export TSV", systemImage: "square.and.arrow.up") }
                .disabled(selectedSessions.isEmpty)
            Button { sendToEndNote(selectedSessions) } label: { Label("Send to EndNote", systemImage: "books.vertical") }
                .disabled(selectedSessions.isEmpty)
                .help("Opens the selected scrape records directly in EndNote")
        }
    }

    private func startScrape() {
        guard let url = URL(string: searchURL), let folder = downloadFolder else { return }
        if let session = scraper.start(searchURL: url, destination: folder, shouldDownloadPDFs: shouldDownloadPDFs, pageLimit: requestedPageCount, context: modelContext) {
            sessionSelections = [session.id]
        }
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
    ContentView().modelContainer(for: [Item.self, ScrapeSession.self, LibraryCollection.self], inMemory: true)
}
