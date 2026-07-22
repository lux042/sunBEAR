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

    func testCIAStructuredNextPageLink() throws {
        let base = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/advanced-search-view?keyword=Germany"))
        let html = """
        <nav class="pager">
          <ul>
            <li class="pager__item pager__item--next">
              <a title="Go to next page" href="?keyword=Germany&amp;page=1">
                <span>Next</span><span aria-hidden="true">›</span>
              </a>
            </li>
          </ul>
        </nav>
        """
        XCTAssertEqual(
            CIAHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString,
            "https://www.cia.gov/readingroom/advanced-search-view?keyword=Germany&page=1"
        )
    }

    func testJSTORResultLinksAndPagination() throws {
        let base = try XCTUnwrap(URL(string: "https://www.jstor.org/action/doBasicSearch?Query=climate"))
        let html = """
        <search-results-vue-pharos-link data-qa="search-result-title-link" data-itemtype="Research Report"
          href="/stable/resrep16372?searchText=climate">Climate Change</search-results-vue-pharos-link>
        <a href="https://www.jstor.org/stable/10.2307/1234">Second result</a>
        <a rel="next" href="?Query=climate&amp;pagemark=eyJwYWdlIjoyfQ%3D%3D">Next</a>
        """

        XCTAssertEqual(JSTORHTMLParser.resultLinks(in: html, baseURL: base).map(\.absoluteString), [
            "https://www.jstor.org/stable/resrep16372",
            "https://www.jstor.org/stable/10.2307/1234"
        ])
        XCTAssertEqual(
            JSTORHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString,
            "https://www.jstor.org/action/doBasicSearch?Query=climate&pagemark=eyJwYWdlIjoyfQ%3D%3D"
        )
    }

    func testJSTORDocumentMetadata() throws {
        let url = try XCTUnwrap(URL(string: "https://www.jstor.org/stable/resrep16372"))
        let html = """
        <meta name="citation_title" content="Climate &amp; Society">
        <meta name="citation_type" content="research report">
        <meta name="citation_publisher" content="Example Institute">
        <meta name="citation_publication_date" content="2012/03/21">
        <meta name="description" content="&lt;p&gt;An article abstract.&lt;/p&gt;">
        <link rel="alternate" href="/stable/pdf/resrep16372.pdf">
        """

        let document = JSTORHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "Climate & Society")
        XCTAssertEqual(document.fields["Document Type"], "research report")
        XCTAssertEqual(document.fields["Collection"], "Example Institute")
        XCTAssertEqual(document.fields["Document Number (FOIA) /ESDN (CREST)"], "resrep16372")
        XCTAssertEqual(document.fields["Publication Date"], "2012/03/21")
        XCTAssertEqual(document.body, "An article abstract.")
        XCTAssertEqual(document.pdfURLs.first?.absoluteString, "https://www.jstor.org/stable/pdf/resrep16372.pdf")
    }

    func testJSTORGeneratesAuthenticatedPDFURLWhenPageDoesNotExposeOne() throws {
        let url = try XCTUnwrap(URL(string: "https://www.jstor.org/stable/44214824"))
        let html = "<meta name=\"citation_title\" content=\"Cuba and the U.S.\">"

        let document = JSTORHTMLParser.document(from: html, url: url)

        XCTAssertEqual(document.pdfURLs.map(\.absoluteString), ["https://www.jstor.org/stable/pdf/44214824.pdf"])
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

    @MainActor
    func testDirectEndNoteImportIncludesCIAFieldsAndAttachment() {
        let item = Item(
            title: "A title", documentType: "CREST", collection: "General CIA Records",
            documentNumber: "CIA-RDP-1", releaseDecision: "RIPPUB", originalClassification: "K",
            pageCount: 3, documentCreationDate: "December 14, 2016",
            documentReleaseDate: "September 27, 2002", sequenceNumber: "9",
            publicationDate: "June 1, 1960", contentType: "MF", caseNumber: "CASE-1",
            recordURL: "https://example.com/record", pdfURLs: ["https://example.com/file.pdf"],
            body: "Summary\nwith a line break", localPDFPaths: ["/tmp/file.pdf"]
        )
        let export = ExportService.endNoteImport(items: [item])

        XCTAssertTrue(export.hasPrefix("%0 CIA\n"))
        XCTAssertTrue(export.contains("%T A title\n"))
        let notesLines = export.components(separatedBy: .newlines).filter { $0.hasPrefix("%Z ") }
        XCTAssertEqual(notesLines.count, 1)
        let notes = notesLines[0]
        XCTAssertTrue(notes.contains("Document Type: CREST"))
        XCTAssertTrue(notes.contains("Collection: General CIA Records"))
        XCTAssertTrue(notes.contains("Document Number (FOIA) / ESDN (CREST): CIA-RDP-1"))
        XCTAssertTrue(notes.contains("Release Decision: RIPPUB"))
        XCTAssertTrue(notes.contains("Original Classification: K"))
        XCTAssertTrue(export.contains("%P 3\n"))
        XCTAssertTrue(notes.contains("Document Creation Date: December 14, 2016"))
        XCTAssertTrue(notes.contains("Document Release Date: September 27, 2002"))
        XCTAssertTrue(notes.contains("Sequence Number: 9"))
        XCTAssertTrue(export.contains("%8 June 1, 1960\n"))
        XCTAssertTrue(notes.contains("Content Type: MF"))
        XCTAssertTrue(notes.contains("Case Number: CASE-1"))
        XCTAssertTrue(export.contains("%U https://example.com/record\n"))
        XCTAssertTrue(export.contains("%U https://example.com/file.pdf\n"))
        XCTAssertLessThan(
            export.range(of: "%U https://example.com/file.pdf")!.lowerBound,
            export.range(of: "%U https://example.com/record")!.lowerBound
        )
        XCTAssertTrue(export.contains("%X Summary with a line break\n"))
        XCTAssertTrue(export.contains("%> /tmp/file.pdf\n"))
        XCTAssertFalse(export.contains("%9 CREST\n"))
    }

    @MainActor
    func testDirectEndNoteXMLUsesCIATypeAndMappedFields() {
        let item = Item(
            title: "A & B", documentType: "CREST", collection: "General CIA Records",
            documentNumber: "CIA-RDP-1", releaseDecision: "RIPPUB", originalClassification: "K",
            pageCount: 3, documentCreationDate: "December 14, 2016",
            documentReleaseDate: "September 27, 2002", sequenceNumber: "9",
            publicationDate: "June 1, 1960", contentType: "MF", caseNumber: "CASE-1",
            recordURL: "https://example.com/record?a=1&b=2",
            pdfURLs: ["https://example.com/file.pdf"], body: "Summary <body>"
        )
        let export = ExportService.endNoteXML(items: [item])

        XCTAssertTrue(export.contains("<ref-type name=\"CIA\">40</ref-type>"))
        XCTAssertTrue(export.contains("A &amp; B"))
        XCTAssertTrue(export.contains("<pages>"))
        XCTAssertTrue(export.contains("June 1, 1960"))
        XCTAssertTrue(export.contains("<notes>"))
        XCTAssertTrue(export.contains("Document Type: CREST"))
        XCTAssertTrue(export.contains("Case Number: CASE-1"))
        XCTAssertTrue(export.contains("https://example.com/file.pdf"))
        XCTAssertTrue(export.contains("https://example.com/record?a=1&amp;b=2"))
        XCTAssertTrue(export.contains("Summary &lt;body&gt;"))
    }

    @MainActor
    func testDirectEndNoteXMLRemovesIllegalPDFControlCharacters() {
        let item = Item(
            title: "Control character test", pageCount: 1,
            recordURL: "https://example.com/record",
            body: "Page one\u{000C}Page two\u{0008}done"
        )

        let export = ExportService.endNoteXML(items: [item])

        XCTAssertFalse(export.contains("\u{000C}"))
        XCTAssertFalse(export.contains("\u{0008}"))
        XCTAssertTrue(export.contains("Page onePage twodone"))
    }

    func testScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://www.cia.gov/readingroom/advanced-search-view?keyword=Cuba"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "Cuba - 2026-07-21 09-37-02")
    }

    func testJSTORScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://www.jstor.org/action/doBasicSearch?Query=climate%20change"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "JSTOR - climate change - 2026-07-21 09-37-02")
    }

    @MainActor
    func testPaginationIsCappedAtTenPages() {
        XCTAssertEqual(ScrapeService.maximumSearchPages, 10)
        XCTAssertEqual(ScrapeService.clampedPageLimit(0), 1)
        XCTAssertEqual(ScrapeService.clampedPageLimit(6), 6)
        XCTAssertEqual(ScrapeService.clampedPageLimit(20), 10)
    }
}
