import XCTest
@testable import sunBEAR

final class sunBEARTests: XCTestCase {
    func testResultLinksAndPagination() throws {
        let base = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/search/site/test"))
        let html = """
        <a href="/readingroom/document/cia-rdp-test">Record</a>
        <a href="/readingroom/document/cia-rdp-test">Duplicate</a>
        <a href="/readingroom/document-view/12345">Advanced search record</a>
        <a href="?page=1" rel="next">Next</a>
        """
        XCTAssertEqual(CIAHTMLParser.resultLinks(in: html, baseURL: base).count, 2)
        XCTAssertEqual(CIAHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString, "https://www.cia.gov/readingroom/search/site/test?page=1")
    }

    func testDocumentMetadataAndAllPDFs() throws {
        let url = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/document/test"))
        let html = """
        <h1>Sample &amp; Record</h1>
        <div>Document Type:</div><div>CREST</div>
        <div>Collection:</div><div>General CIA Records</div>
        <div>Document Page Count:</div><div>12</div>
        <div>File:</div>
        <a href="/readingroom/docs/one.pdf">One</a>
        <a href="/readingroom/docs/two.PDF">Two</a>
        <div>Body:</div><p>Abstract text</p>
        """
        let document = CIAHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "Sample & Record")
        XCTAssertEqual(document.fields["Document Type"], "CREST")
        XCTAssertEqual(document.fields["Document Page Count"], "12")
        XCTAssertEqual(document.pdfURLs.count, 2)
        XCTAssertTrue(document.body.contains("Abstract text"))
    }

    func testClassicPageIgnoresLibraryHeadingAndHandlesFieldOrder() throws {
        let url = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/document/test"))
        let html = """
        <h1>Library</h1>
        <h2>SUMMARY OF U-2 OPERATIONAL MISSIONS FLOWN SINCE 1 MAY 1960</h2>
        <div>Document Type: CREST</div>
        <div>Sequence Number: 9</div>
        <div>Case Number:</div>
        <div>Publication Date: September 21, 1962</div>
        <div>Content Type: MF</div>
        <div>File:</div><a href="/readingroom/docs/test.pdf">PDF</a>
        <div>Body:</div><p>Long OCR abstract text.</p>
        <a>Printer-friendly version</a>
        """
        let document = CIAHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "SUMMARY OF U-2 OPERATIONAL MISSIONS FLOWN SINCE 1 MAY 1960")
        XCTAssertEqual(document.fields["Case Number"], "")
        XCTAssertEqual(document.fields["Publication Date"], "September 21, 1962")
        XCTAssertEqual(document.fields["Content Type"], "MF")
        XCTAssertEqual(document.body, "Long OCR abstract text.")
    }

    @MainActor
    func testEndNoteExportMarkerAndMappedHeaders() {
        let item = Item(title: "A title", documentType: "CREST", collection: "General CIA Records", documentNumber: "CIA-RDP-1", releaseDecision: "RIPPUB", originalClassification: "K", pageCount: 3, documentCreationDate: "December 14, 2016", documentReleaseDate: "September 27, 2002", sequenceNumber: "9", publicationDate: "June 1, 1960", contentType: "MF", caseNumber: "CASE-1", recordURL: "https://example.com/record", pdfURLs: ["https://example.com/file.pdf"], body: "Summary")
        let export = ExportService.endNoteTSV(items: [item])
        let lines = export.components(separatedBy: .newlines)
        XCTAssertFalse(export.hasPrefix("*CIA"))
        let headers = lines[0].components(separatedBy: "\t")
        let values = lines[1].components(separatedBy: "\t")
        XCTAssertEqual(headers, ExportService.headers)
        XCTAssertEqual(headers.count, 16)
        XCTAssertEqual(values.count, 16)
        XCTAssertEqual(values[1], "CREST")
        XCTAssertEqual(values[2], "General CIA Records")
        XCTAssertEqual(values[6], "3")
        XCTAssertEqual(values[10], "June 1, 1960")
        XCTAssertEqual(values[13], "https://example.com/record")
        XCTAssertEqual(values[14], "https://example.com/file.pdf")
        XCTAssertEqual(values[15], "Summary")
    }

    func testScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/advanced-search-view?keyword=Cuba"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "Cuba - 2026-07-21 09-37-02")
    }

    @MainActor
    func testPaginationIsCappedAtTenPages() {
        XCTAssertEqual(ScrapeService.maximumSearchPages, 10)
    }
}
