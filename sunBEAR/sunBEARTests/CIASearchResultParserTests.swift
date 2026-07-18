import Foundation
import XCTest
@testable import sunBEAR

final class CIASearchResultParserTests: XCTestCase {
    func testEmptyHTMLReturnsNoResults() {
        let parser = CIASearchResultParser()
        let baseURL = URL(string: "https://www.cia.gov")!

        let results = parser.parse(
            html: "",
            baseURL: baseURL
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testParsesOneDocumentLink() {
        let parser = CIASearchResultParser()
        let baseURL = URL(
            string: "https://www.cia.gov/readingroom/advanced-search-view"
        )!

        let html = """
        <a href="/readingroom/document/cia-rdp-example">
            Example CIA Document
        </a>
        """

        let results = parser.parse(
            html: html,
            baseURL: baseURL
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Example CIA Document")
        XCTAssertEqual(
            results.first?.documentURL.absoluteString,
            "https://www.cia.gov/readingroom/document/cia-rdp-example"
        )
    }

    func testParsesSavedEcuadorResultsPage() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryURL
            .appendingPathComponent("SampleData")
            .appendingPathComponent("ecuador-search-results.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let baseURL = URL(
            string: "https://www.cia.gov/readingroom/advanced-search-view?keyword=ecuador"
        )!

        let page = CIASearchResultParser().parsePage(
            html: html,
            baseURL: baseURL
        )
        let results = page.results

        XCTAssertEqual(results.count, 20)
        XCTAssertEqual(
            results.first?.title,
            "FINAL DEMARCATION OF ECUADOR-PERU BOUNDARY"
        )
        XCTAssertEqual(
            results.first?.documentURL.absoluteString,
            "https://www.cia.gov/readingroom/document/cia-rdp08c01297r000700110011-3"
        )
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://www.cia.gov/readingroom/advanced-search-view?keyword=ecuador&label=&sm_field_document_number=&sm_field_original_classification=&ds_field_pub_date_op=%3D&ds_field_pub_date%5Bvalue%5D=&ds_field_pub_date%5Bmin%5D=&ds_field_pub_date%5Bmax%5D=&sm_field_content_type=&sm_field_case_number=&page=1"
        )
    }

    func testPageWithoutNextLinkEndsPagination() {
        let baseURL = URL(string: "https://www.cia.gov/readingroom/advanced-search-view")!
        let html = """
        <a href="/readingroom/document/example">Example</a>
        """

        let page = CIASearchResultParser().parsePage(html: html, baseURL: baseURL)

        XCTAssertEqual(page.results.count, 1)
        XCTAssertNil(page.nextPageURL)
    }
}
