import Foundation
import SwiftSoup

struct CIASearchResultParser: Sendable {
    func parse(html: String, baseURL: URL) -> [CIASearchResult] {
        parsePage(html: html, baseURL: baseURL).results
    }

    func parsePage(html: String, baseURL: URL) -> CIASearchResultPage {
        guard let document = try? SwiftSoup.parse(
            html,
            baseURL.absoluteString
        ) else {
            return CIASearchResultPage(results: [], nextPageURL: nil)
        }

        guard let links = try? document.select(
            "a[href*=/readingroom/document/]"
        ) else {
            return CIASearchResultPage(results: [], nextPageURL: nil)
        }

        let results: [CIASearchResult] = links.compactMap { link -> CIASearchResult? in
            guard
                let title = try? link.text(),
                !title.isEmpty,
                let href = try? link.attr("abs:href"),
                let documentURL = URL(string: href)
            else {
                return nil
            }

            return CIASearchResult(
                title: title,
                documentURL: documentURL,
                documentNumber: nil
            )
        }

        let nextPageURL: URL? = {
            guard
                let href = try? document
                    .select(".pager-next a[href]")
                    .first()?
                    .attr("abs:href"),
                !href.isEmpty
            else {
                return nil
            }

            return URL(string: href)
        }()

        return CIASearchResultPage(
            results: results,
            nextPageURL: nextPageURL
        )
    }
}
