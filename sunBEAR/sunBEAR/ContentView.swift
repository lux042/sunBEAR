import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScrapeJob.createdAt, order: .reverse) private var jobs: [ScrapeJob]

    @State private var selection: AppSection? = .search
    @State private var searchTerms = ""
    @State private var maximumPages = 1
    @State private var isRunning = false
    @State private var progressText: String?
    @State private var searchError: String?
    @State private var showLargeSearchWarning = false
    @State private var approvedDocumentBudget = 100
    @State private var jobPendingDeletion: ScrapeJob?
    @State private var showCIAReadingRoom = false
    @State private var selectedLibraryJob: ScrapeJob?

    private let defaultDocumentBudget = 100

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("sunBEAR")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .scrollContentBackground(.hidden)
            .background(Color.sunBearNavy)
        } detail: {
            switch selection ?? .search {
            case .search:
                searchView
            case .library:
                libraryView
            }
        }
        .tint(.sunBearGold)
        .preferredColorScheme(.dark)
        .background(Color.sunBearNavy)
    }

    private var searchView: some View {
        Form {
            Section("CIA FOIA Search") {
                Text("Search normally in the CIA page, then import the visible results. sunBEAR imports one page at a time and preserves the browser session.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Open CIA Advanced Search", systemImage: "globe") {
                    showCIAReadingRoom = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                if isRunning {
                    ProgressView(progressText ?? "Starting search…")
                }

                if let searchError {
                    Text(searchError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.sunBearNavy)
        .navigationTitle("Search")
        .frame(minWidth: 520, minHeight: 400)
        .alert("Large CIA Search", isPresented: $showLargeSearchWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Continue Carefully") {
                approvedDocumentBudget = estimatedDocumentRequests
                Task { await runSearch() }
            }
        } message: {
            Text("This search may request up to \(estimatedDocumentRequests) document pages and could take a long time. sunBEAR will keep requests sequential and rate-limited.")
        }
        .sheet(isPresented: $showCIAReadingRoom) {
            CIAReadingRoomBrowserView()
        }
    }

    private var libraryView: some View {
        Group {
            if let selectedLibraryJob {
                NavigationStack {
                    LibraryJobDetailView(job: selectedLibraryJob) {
                        self.selectedLibraryJob = nil
                    }
                }
            } else if jobs.isEmpty {
                ContentUnavailableView(
                    "No Saved Searches",
                    systemImage: "books.vertical",
                    description: Text("Saved CIA searches will appear here.")
                )
            } else {
                List {
                    ForEach(jobs) { job in
                        HStack {
                            Button {
                                selectedLibraryJob = job
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(job.displayName)
                                        .font(.headline)

                                    HStack(spacing: 12) {
                                        Label(job.status.displayName, systemImage: "circle.fill")
                                        Text("\(job.maximumPages) page\(job.maximumPages == 1 ? "" : "s")")
                                        Text("\(job.documents.count) documents")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)

                            Button("Delete \(job.displayName)", systemImage: "trash", role: .destructive) {
                                jobPendingDeletion = job
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Delete this saved search")
                        }
                    }
                    .onDelete(perform: deleteJobs)
                }
                .scrollContentBackground(.hidden)
                .background(Color.sunBearNavy)
            }
        }
        .navigationTitle("Library")
        .confirmationDialog(
            "Delete this saved search?",
            isPresented: Binding(
                get: { jobPendingDeletion != nil },
                set: { if !$0 { jobPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let job = jobPendingDeletion {
                    delete(job)
                }
                jobPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                jobPendingDeletion = nil
            }
        } message: {
            Text("Its saved document metadata will also be deleted. This cannot be undone.")
        }
    }

    private var estimatedDocumentRequests: Int { maximumPages * 20 }

    private func beginSearch() {
        approvedDocumentBudget = min(defaultDocumentBudget, estimatedDocumentRequests)
        if estimatedDocumentRequests > defaultDocumentBudget {
            showLargeSearchWarning = true
        } else {
            Task { await runSearch() }
        }
    }

    @MainActor
    private func runSearch() async {
        var query = CIASearchQuery()
        query.searchTerms = searchTerms
        query.maximumPages = maximumPages
        query.maximumDocumentRequests = approvedDocumentBudget

        let job = ScrapeJob(query: query)
        job.status = .running
        modelContext.insert(job)
        try? modelContext.save()
        selection = .library

        isRunning = true
        searchError = nil
        progressText = "Fetching CIA results…"

        do {
            let result = try await CIAScrapeRunner().run(query: query) { progress in
                await MainActor.run {
                    job.pagesCompleted = progress.pagesCompleted
                    job.documentsDiscovered = progress.documentsDiscovered
                    job.documentsParsed = progress.documentsParsed
                    job.updatedAt = .now
                    progressText = "Page \(progress.pagesCompleted): parsed \(progress.documentsParsed) of \(progress.documentsDiscovered) documents"
                    try? modelContext.save()
                }
            }

            for record in result.records {
                let savedDocument = SavedCIADocument(record: record, job: job)
                modelContext.insert(savedDocument)
                job.documents.append(savedDocument)
            }
            job.pagesCompleted = result.pagesCompleted
            job.documentsDiscovered = result.records.count
            job.documentsParsed = result.records.count
            job.status = .completed
            job.updatedAt = .now

            do {
                let tsvURL = try MetadataTSVExporter().export(
                    records: result.records,
                    jobID: job.id,
                    displayName: job.displayName
                )
                job.endNoteTSVPath = tsvURL.path
            } catch {
                job.lastErrorMessage = "Metadata was saved, but TSV export failed: \(error.localizedDescription)"
            }

            try modelContext.save()
            progressText = "Completed: saved \(result.records.count) documents"
        } catch {
            job.status = job.documentsParsed > 0 ? .partial : .failed
            job.lastErrorMessage = error.localizedDescription
            job.updatedAt = .now
            try? modelContext.save()
            searchError = error.localizedDescription
        }

        isRunning = false
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(jobs[index])
        }
        try? modelContext.save()
    }

    private func delete(_ job: ScrapeJob) {
        if selectedLibraryJob?.id == job.id {
            selectedLibraryJob = nil
        }
        modelContext.delete(job)
        try? modelContext.save()
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case search
    case library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: "Search"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, ScrapeJob.self, SavedCIADocument.self], inMemory: true)
}

private struct LibraryJobDetailView: View {
    let job: ScrapeJob
    let onBackToLibrary: () -> Void

    var body: some View {
        List {
            Section("Search") {
                LabeledContent("Status", value: job.status.displayName)
                LabeledContent("Pages", value: "\(job.pagesCompleted) of \(job.maximumPages)")
                LabeledContent("Documents", value: "\(job.documents.count)")
            }

            if let errorMessage = job.lastErrorMessage, !errorMessage.isEmpty {
                Section("Problem") {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            if job.preservationTSVPath != nil || job.endNoteTSVPath != nil {
                Section("Metadata Files") {
                    if let path = job.preservationTSVPath {
                        Link("Open Preservation TSV", destination: URL(fileURLWithPath: path))
                    }
                    if let path = job.endNoteTSVPath {
                        let fileURL = URL(fileURLWithPath: path)
                        LabeledContent("Metadata TSV") {
                            Text(fileURL.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        HStack {
                            Button("Open TSV", systemImage: "doc.text") {
#if os(macOS)
                                NSWorkspace.shared.open(fileURL)
#endif
                            }
                                .buttonStyle(.borderedProminent)

#if os(macOS)
                            Button("Show in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                            }
                            .buttonStyle(.bordered)
#endif
                        }
                    }
                }
            } else if job.status == .completed {
                Section("Metadata Files") {
                    ContentUnavailableView(
                        "No TSV Generated",
                        systemImage: "doc.badge.ellipsis",
                        description: Text("TSV export is created for newly completed searches.")
                    )
                }
            }

            Section("Saved Documents") {
                if job.documents.isEmpty {
                    Text("No document metadata has been saved for this search yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(job.documents) { document in
                        NavigationLink {
                            SavedDocumentDetailView(document: document)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title)
                                Text(document.documentNumber ?? "No document number")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(job.displayName)
        .scrollContentBackground(.hidden)
        .background(Color.sunBearNavy)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Library", systemImage: "chevron.left") {
                    onBackToLibrary()
                }
            }
        }
    }
}

private struct SavedDocumentDetailView: View {
    let document: SavedCIADocument

    var body: some View {
        List {
            Section("Document") {
                metadataRow("Title", document.title)
                metadataRow("Document Type", document.documentType)
                metadataRow("Collection", document.collection)
                metadataRow("Document Number (FOIA) /ESDN (CREST)", document.documentNumber)
                metadataRow("Release Decision", document.releaseDecision)
                metadataRow("Original Classification", document.originalClassification)
                metadataRow("Document Page Count", document.documentPageCount.map(String.init))
                metadataRow("Document Creation Date", document.documentCreationDate)
                metadataRow("Document Release Date", document.documentReleaseDate)
                metadataRow("Sequence Number", document.sequenceNumber)
                metadataRow("Publication Date", document.publicationDate)
                metadataRow("Content Type", document.contentType)
                metadataRow("Case Number", document.caseNumber)
            }

            Section("Links") {
                if let sourceURL = document.sourceURL {
                    Link("Open CIA Record", destination: sourceURL)
                }
                if let pdfURL = document.pdfURL {
                    Link("Open PDF", destination: pdfURL)
                }
            }

            if let body = document.body, !body.isEmpty {
                Section("Body") {
                    Text(body)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(document.title)
        .scrollContentBackground(.hidden)
        .background(Color.sunBearNavy)
    }

    private func metadataRow(_ label: String, _ value: String?) -> some View {
        LabeledContent(label, value: value ?? "—")
    }
}

extension Color {
    static let sunBearNavy = Color(red: 0.035, green: 0.075, blue: 0.14)
    static let sunBearGold = Color(red: 0.95, green: 0.60, blue: 0.09)
}
