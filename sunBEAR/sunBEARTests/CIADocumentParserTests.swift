import Foundation
import XCTest
@testable import sunBEAR

final class CIADocumentParserTests: XCTestCase {
    func testParsesSavedEcuadorDocument() throws {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryURL
            .appendingPathComponent("SampleData")
            .appendingPathComponent("ecuador-document-detail.html")
        let html = try String(contentsOf: fixtureURL, encoding: .utf8)
        let sourceURL = URL(
            string: "https://www.cia.gov/readingroom/document/cia-rdp08c01297r000700110011-3"
        )!

        let record = try XCTUnwrap(
            CIADocumentParser().parse(html: html, sourceURL: sourceURL)
        )

        XCTAssertEqual(record.title, "FINAL DEMARCATION OF ECUADOR-PERU BOUNDARY")
        XCTAssertEqual(record.documentType, "CREST")
        XCTAssertEqual(record.collection, "General CIA Records")
        XCTAssertEqual(record.documentNumber, "CIA-RDP08C01297R000700110011-3")
        XCTAssertEqual(record.releaseDecision, "RIPPUB")
        XCTAssertEqual(record.originalClassification, "C")
        XCTAssertEqual(record.documentPageCount, 3)
        XCTAssertEqual(record.documentCreationDate, "2016-12-27")
        XCTAssertEqual(record.documentReleaseDate, "2012-10-02")
        XCTAssertEqual(record.sequenceNumber, "11")
        XCTAssertEqual(record.publicationDate, "1945-07-24")
        XCTAssertEqual(record.contentType, "REPORT")
        XCTAssertNil(record.caseNumber)
        XCTAssertTrue(record.body?.contains("Final Demarcation of Ecuador-Peru Boundary") == true)
        XCTAssertEqual(
            record.pdfURL?.absoluteString,
            "https://www.cia.gov/readingroom/docs/CIA-RDP08C01297R000700110011-3.pdf"
        )
        XCTAssertEqual(record.rawMetadata["Document Page Count"], "3")
        XCTAssertEqual(
            record.rawMetadata["Document Number (FOIA) /ESDN (CREST)"],
            "CIA-RDP08C01297R000700110011-3"
        )
    }

    func testReturnsNilWhenDocumentTitleIsMissing() {
        let sourceURL = URL(string: "https://www.cia.gov/readingroom/document/example")!

        XCTAssertNil(CIADocumentParser().parse(html: "<html></html>", sourceURL: sourceURL))
    }
}
