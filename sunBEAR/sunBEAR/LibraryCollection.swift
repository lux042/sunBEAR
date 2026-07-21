import Foundation
import SwiftData

@Model
final class LibraryCollection {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ScrapeSession.libraryCollection) var sessions: [ScrapeSession]

    init(name: String, createdAt: Date = .now, sessions: [ScrapeSession] = []) {
        self.name = name
        self.createdAt = createdAt
        self.sessions = sessions
    }
}
