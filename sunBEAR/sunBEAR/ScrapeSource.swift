import Foundation

enum ScrapeSource: String, CaseIterable, Identifiable {
    case cia
    case jstor

    var id: Self { self }

    var title: String {
        switch self {
        case .cia: "CIA FOIA"
        case .jstor: "JSTOR"
        }
    }

    var homeURL: URL {
        switch self {
        case .cia: URL(string: "https://www.cia.gov/readingroom/advanced-search-view")!
        case .jstor: URL(string: "https://www.jstor.org/")!
        }
    }

    var defaultSearchURL: String {
        switch self {
        case .cia: "https://www.cia.gov/readingroom/search/site"
        case .jstor: "https://www.jstor.org/action/doBasicSearch"
        }
    }

    var searchURLPrompt: String { "\(title) search-results URL" }

    func canImport(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased().hasSuffix(hostSuffix) == true else { return false }
        switch self {
        case .cia: return url.path.localizedCaseInsensitiveContains("search")
        case .jstor: return url.path.contains("/action/doBasicSearch") || url.path.contains("/action/doAdvancedSearch")
        }
    }

    static func source(for url: URL) -> ScrapeSource? {
        allCases.first { url.host?.lowercased().hasSuffix($0.hostSuffix) == true }
    }

    private var hostSuffix: String {
        switch self {
        case .cia: "cia.gov"
        case .jstor: "jstor.org"
        }
    }
}
