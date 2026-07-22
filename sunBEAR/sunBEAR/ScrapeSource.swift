import Foundation

enum ScrapeSource: String, CaseIterable, Identifiable {
    case cia
    case jstor
    case eric
    case pubmed

    var id: Self { self }

    var title: String {
        switch self {
        case .cia: "CIA FOIA"
        case .jstor: "JSTOR"
        case .eric: "ERIC"
        case .pubmed: "PubMed"
        }
    }

    var homeURL: URL {
        switch self {
        case .cia: URL(string: "https://www.cia.gov/readingroom/advanced-search-view")!
        case .jstor: URL(string: "https://www.jstor.org/")!
        case .eric: URL(string: "https://eric.ed.gov/")!
        case .pubmed: URL(string: "https://pubmed.ncbi.nlm.nih.gov/")!
        }
    }

    var defaultSearchURL: String {
        switch self {
        case .cia: "https://www.cia.gov/readingroom/search/site"
        case .jstor: "https://www.jstor.org/action/doBasicSearch"
        case .eric: "https://eric.ed.gov/"
        case .pubmed: "https://pubmed.ncbi.nlm.nih.gov/"
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
        }
    }
}
