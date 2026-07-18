import Foundation

struct CIASearchResult: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let documentURL: URL
    let documentNumber: String?
}
