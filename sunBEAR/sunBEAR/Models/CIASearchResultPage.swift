import Foundation

struct CIASearchResultPage: Hashable, Sendable {
    let results: [CIASearchResult]
    let nextPageURL: URL?
}
