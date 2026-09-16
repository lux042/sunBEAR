import Foundation

enum ScrapeSource: String, CaseIterable, Identifiable {
    case cia
    case jstor
    case eric
    case pubmed
    case nara
    case nyt

    var id: Self { self }

    var title: String {
        switch self {
        case .cia: "CIA FOIA"
        case .jstor: "JSTOR"
        case .eric: "ERIC"
        case .pubmed: "PubMed"
        case .nara: "National Archives"
        case .nyt: "New York Times"
        }
    }

    var homeURL: URL {
        switch self {
        case .cia: URL(string: "https://www.cia.gov/readingroom/advanced-search-view")!
        case .jstor: URL(string: "https://www.jstor.org/")!
        case .eric: URL(string: "https://eric.ed.gov/")!
        case .pubmed: URL(string: "https://pubmed.ncbi.nlm.nih.gov/")!
        case .nara: URL(string: "https://catalog.archives.gov/")!
        case .nyt: URL(string: "https://www.nytimes.com/search")!
        }
    }

    var defaultSearchURL: String {
        switch self {
        case .cia: "https://www.cia.gov/readingroom/search/site"
        case .jstor: "https://www.jstor.org/action/doBasicSearch"
        case .eric: "https://eric.ed.gov/"
        case .pubmed: "https://pubmed.ncbi.nlm.nih.gov/"
        case .nara: "https://catalog.archives.gov/search?page=1&q="
        case .nyt: "https://www.nytimes.com/search?query="
        }
    }

    var searchURLPrompt: String { "\(title) search-results URL" }

    func canImport(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased().hasSuffix(hostSuffix) == true else { return false }
        switch self {
        case .cia: return url.path.localizedCaseInsensitiveContains("search")
        case .jstor: return url.path.contains("/action/doBasicSearch") || url.path.contains("/action/doAdvancedSearch")
        case .eric:
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return query.contains { $0.name == "q" } && !query.contains { $0.name == "id" }
        case .pubmed:
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return query.contains { $0.name == "term" }
        case .nara:
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return url.path == "/search" && query.contains { $0.name == "q" && !($0.value ?? "").isEmpty }
        case .nyt:
            return NewYorkTimesHTMLParser.isSearch(url) || NewYorkTimesHTMLParser.isArticle(url)
        }
    }

    static func source(for url: URL) -> ScrapeSource? {
        allCases.first { url.host?.lowercased().hasSuffix($0.hostSuffix) == true }
    }

    private var hostSuffix: String {
        switch self {
        case .cia: "cia.gov"
        case .jstor: "jstor.org"
        case .eric: "eric.ed.gov"
        case .pubmed: "pubmed.ncbi.nlm.nih.gov"
        case .nara: "catalog.archives.gov"
        case .nyt: "nytimes.com"
        }
    }
}
