import Foundation

struct CIASearchQuery: Codable, Hashable, Sendable {
    var searchTerms = ""
    var collectionIDs: Set<String> = []
    var documentTitle = ""
    var documentNumberOrESDN = ""
    var originalClassification = ""
    var publicationDateOperator: PublicationDateOperator = .equal
    var publicationDate: Date?
    var contentType = ""
    var caseNumber = ""

    /// The maximum number of CIA result pages the user wants to scrape.
    var maximumPages = 1

    /// A safety ceiling for individual document-detail requests.
    var maximumDocumentRequests = 100
}

enum PublicationDateOperator: String, Codable, CaseIterable, Identifiable, Sendable {
    case equal = "="
    case before = "<"
    case after = ">"
    case beforeOrEqual = "<="
    case afterOrEqual = ">="

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .equal: "Is equal to"
        case .before: "Is before"
        case .after: "Is after"
        case .beforeOrEqual: "Is before or equal to"
        case .afterOrEqual: "Is after or equal to"
        }
    }
}
