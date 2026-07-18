import Foundation

struct CIASearchRequestBuilder {
    private let endpoint = URL(string: "https://www.cia.gov/readingroom/advanced-search-view")!

    func makeURL(for query: CIASearchQuery) -> URL? {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "keyword", value: query.searchTerms),
            URLQueryItem(name: "label", value: query.documentTitle),
            URLQueryItem(name: "sm_field_document_number", value: query.documentNumberOrESDN),
            URLQueryItem(name: "sm_field_original_classification", value: query.originalClassification),
            URLQueryItem(name: "ds_field_pub_date_op", value: query.publicationDateOperator.rawValue),
            URLQueryItem(name: "ds_field_pub_date[value]", value: formatted(query.publicationDate)),
            URLQueryItem(name: "ds_field_pub_date[min]", value: ""),
            URLQueryItem(name: "ds_field_pub_date[max]", value: ""),
            URLQueryItem(name: "sm_field_content_type", value: query.contentType),
            URLQueryItem(name: "sm_field_case_number", value: query.caseNumber),
        ]

        for collectionID in query.collectionIDs.sorted() {
            items.append(URLQueryItem(name: "im_field_collection[]", value: collectionID))
        }

        components?.queryItems = items
        return components?.url
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
    }
}
