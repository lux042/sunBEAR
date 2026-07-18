import Foundation
import SwiftData

@Model
final class ScrapeJob {
    var id: UUID
    var searchTerms: String
    var createdAt: Date
    var updatedAt: Date
    var statusRawValue: String
    var maximumPages: Int
    var pagesCompleted: Int
    var documentsDiscovered: Int
    var documentsParsed: Int
    var completionPercentage: Int = 0
    var pdfsDownloaded: Int
    var searchJSON: Data
    var lastErrorMessage: String?
    var preservationTSVPath: String?
    var endNoteTSVPath: String?
    @Relationship(deleteRule: .cascade, inverse: \SavedCIADocument.job)
    var documents: [SavedCIADocument]

    init(query: CIASearchQuery, createdAt: Date = .now) {
        id = UUID()
        searchTerms = query.searchTerms
        self.createdAt = createdAt
        updatedAt = createdAt
        statusRawValue = ScrapeJobStatus.saved.rawValue
        maximumPages = query.maximumPages
        pagesCompleted = 0
        documentsDiscovered = 0
        documentsParsed = 0
        completionPercentage = 0
        pdfsDownloaded = 0
        searchJSON = (try? JSONEncoder().encode(query)) ?? Data()
        documents = []
    }

    var status: ScrapeJobStatus {
        get { ScrapeJobStatus(rawValue: statusRawValue) ?? .saved }
        set { statusRawValue = newValue.rawValue }
    }

    var displayName: String {
        let trimmedTerms = searchTerms.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryName = trimmedTerms.isEmpty ? "Advanced Search" : trimmedTerms

        return "\(queryName) — \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

enum ScrapeJobStatus: String, Codable, CaseIterable {
    case saved
    case queued
    case running
    case paused
    case completed
    case partial
    case failed

    var displayName: String { rawValue.capitalized }
}
