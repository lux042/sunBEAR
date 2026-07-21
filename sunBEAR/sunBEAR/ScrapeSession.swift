import Foundation
import SwiftData

@Model
final class ScrapeSession {
    var name: String
    var searchURL: String
    var folderPath: String
    var startedAt: Date
    var pagesScraped: Int
    var isComplete: Bool
    @Relationship(deleteRule: .cascade, inverse: \Item.session) var items: [Item]

    init(name: String, searchURL: String, folderPath: String = "", startedAt: Date = .now, pagesScraped: Int = 0, isComplete: Bool = false, items: [Item] = []) {
        self.name = name
        self.searchURL = searchURL
        self.folderPath = folderPath
        self.startedAt = startedAt
        self.pagesScraped = pagesScraped
        self.isComplete = isComplete
        self.items = items
    }
}
