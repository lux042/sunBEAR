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

    func testERICResultLinksAndPagination() throws {
        let base = try XCTUnwrap(URL(string: "https://eric.ed.gov/?q=english"))
        let html = """
        <div class="r_i" id="r_EJ1458636"><div class="r_t">
          <a href="?q=english&amp;id=EJ1458636">First result</a>
        </div></div>
        <a href="?id=ED636970&amp;q=english">Second result</a>
        <a href="?q=english&amp;pg=2">Next Page »</a>
        """

        XCTAssertEqual(ERICHTMLParser.resultLinks(in: html, baseURL: base).map(\.absoluteString), [
            "https://eric.ed.gov/?id=EJ1458636",
            "https://eric.ed.gov/?id=ED636970"
        ])
        XCTAssertEqual(ERICHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString, "https://eric.ed.gov/?q=english&pg=2")
    }

    func testERICDocumentMetadataAndHostedPDF() throws {
        let url = try XCTUnwrap(URL(string: "https://eric.ed.gov/?id=EJ1458636"))
        let html = """
        <meta name="citation_title" content="A Practitioner&apos;s Conceptualization of Student Engagement." />
        <meta name="citation_abstract" content="A concise study abstract." />
        <meta name="citation_journal_title" content="Advocate" />
        <meta name="citation_publication_date" content="2024/00/00" />
        <meta name="citation_pdf_url" content="http://files.eric.ed.gov/fulltext/EJ1458636.pdf" />
        <div><strong>ERIC Number:</strong> EJ1458636</div>
        <div><strong>Record Type:</strong> Journal</div>
        <div><strong>Pages:</strong> 11</div>
        """

        let document = ERICHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "A Practitioner's Conceptualization of Student Engagement")
        XCTAssertEqual(document.fields["Document Type"], "Journal")
        XCTAssertEqual(document.fields["Collection"], "Advocate")
        XCTAssertEqual(document.fields["Document Number (FOIA) /ESDN (CREST)"], "EJ1458636")
        XCTAssertEqual(document.fields["Document Page Count"], "11")
        XCTAssertEqual(document.fields["Publication Date"], "2024/00/00")
        XCTAssertEqual(document.body, "A concise study abstract.")
        XCTAssertEqual(document.pdfURLs.map(\.absoluteString), ["http://files.eric.ed.gov/fulltext/EJ1458636.pdf"])
    }

    func testERICScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://eric.ed.gov/?q=english"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "ERIC - english - 2026-07-21 09-37-02")
    }

    func testPubMedResultLinksAndPagination() throws {
        let base = try XCTUnwrap(URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=education"))
        let html = """
        <a class="docsum-title" href="/31235301/">First record</a>
        <a class="docsum-title highlighted" href="/41657923/">Second record</a>
        <button class="button-wrapper next-page-btn">Next</button>
        """

        XCTAssertEqual(PubMedHTMLParser.resultLinks(in: html, baseURL: base).map(\.absoluteString), [
            "https://pubmed.ncbi.nlm.nih.gov/31235301/",
            "https://pubmed.ncbi.nlm.nih.gov/41657923/"
        ])
        XCTAssertEqual(PubMedHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString, "https://pubmed.ncbi.nlm.nih.gov/?term=education&page=2")
    }

    func testPubMedMetadataAndPMCDiscovery() throws {
        let url = try XCTUnwrap(URL(string: "https://pubmed.ncbi.nlm.nih.gov/41657923/"))
        let html = """
        <meta name="citation_title" content="What is medical education research?">
        <meta name="citation_date" content="01/15/2026">
        <meta name="citation_journal_title" content="GMS journal for medical education">
        <meta name="citation_pmid" content="41657923">
        <span class="publication-type">Research Article</span>
        <div class="abstract-content selected"><p>A useful <b>medical education</b> abstract.</p></div>
        <a href="https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/">PMC</a>
        """

        let document = PubMedHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "What is medical education research?")
        XCTAssertEqual(document.fields["Document Type"], "Research Article")
        XCTAssertEqual(document.fields["Collection"], "GMS journal for medical education")
        XCTAssertEqual(document.fields["Document Number (FOIA) /ESDN (CREST)"], "41657923")
        XCTAssertEqual(document.fields["Publication Date"], "01/15/2026")
        XCTAssertEqual(document.body, "A useful medical education abstract.")
        XCTAssertTrue(document.pdfURLs.isEmpty)
        XCTAssertEqual(PubMedHTMLParser.pmcArticleURL(in: html, baseURL: url)?.absoluteString, "https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/")
    }

    func testPubMedExtractsOnlyPMCHostedPDFs() throws {
        let base = try XCTUnwrap(URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/"))
        let html = """
        <meta name="citation_pdf_url" content="https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/pdf/JME-43-12.pdf">
        <a href="https://publisher.example/article.pdf">Publisher PDF</a>
        """
        XCTAssertEqual(PubMedHTMLParser.pdfURLs(in: html, baseURL: base).map(\.absoluteString), [
            "https://pmc.ncbi.nlm.nih.gov/articles/PMC12875206/pdf/JME-43-12.pdf"
        ])
    }

    func testPubMedScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://pubmed.ncbi.nlm.nih.gov/?term=medical+education"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "PubMed - medical education - 2026-07-21 09-37-02")
    }

    func testNationalArchivesResultLinksAndPagination() throws {
        let base = try XCTUnwrap(URL(string: "https://catalog.archives.gov/search?page=1&q=constitution"))
        let html = """
        <a href="/id/1667751"><h2>Constitution of the United States</h2></a>
        <a href="/id/513007">Constitution</a>
        <button aria-label="Go to page 2">Next</button>
        """
        XCTAssertEqual(NARAHTMLParser.resultLinks(in: html, baseURL: base).map(\.absoluteString), [
            "https://catalog.archives.gov/id/1667751",
            "https://catalog.archives.gov/id/513007"
        ])
        XCTAssertEqual(NARAHTMLParser.nextPage(in: html, baseURL: base)?.absoluteString, "https://catalog.archives.gov/search?q=constitution&page=2")
    }

    func testNationalArchivesMetadataAndPDFs() throws {
        let url = try XCTUnwrap(URL(string: "https://catalog.archives.gov/id/1667751"))
        let html = """
        <main><div>Item</div><h1>Constitution of the United States</h1><div>NAID: 1667751</div>
        <a href="https://catalog.archives.gov/medialive/archive/00303.pdf">Download the PDF</a>
        <h2>Dates,</h2><p>September 17, 1787–September 17, 1787.</p>
        <h2>Record Group 11</h2><div>General Records of the United States Government</div>
        <h2>Scope and Content</h2><p>The signed parchment copy.</p></main>
        """
        let document = NARAHTMLParser.document(from: html, url: url)
        XCTAssertEqual(document.title, "Constitution of the United States")
        XCTAssertEqual(document.fields["Document Type"], "Item")
        XCTAssertEqual(document.fields["Document Number (FOIA) /ESDN (CREST)"], "1667751")
        XCTAssertEqual(document.fields["Collection"], "General Records of the United States Government")
        XCTAssertEqual(document.fields["Publication Date"], "September 17, 1787–September 17, 1787.")
        XCTAssertEqual(document.fields["Content Type"], "National Archives")
        XCTAssertEqual(document.body, "The signed parchment copy.")
        XCTAssertEqual(document.pdfURLs.map(\.absoluteString), ["https://catalog.archives.gov/medialive/archive/00303.pdf"])
    }

    func testNationalArchivesScrapeFolderUsesSearchAndTimestamp() throws {
        let url = try XCTUnwrap(URL(string: "https://catalog.archives.gov/search?page=1&q=constitution"))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 7, day: 21, hour: 14, minute: 37, second: 2)))
        XCTAssertEqual(ScrapeFolderNaming.folderName(for: url, date: date), "National Archives - constitution - 2026-07-21 09-37-02")
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

    @MainActor
    func testJSTORERICAndPubMedUseSourceAwareEndNoteFields() {
        let jstor = Item(
            title: "JSTOR article", documentType: "Journal Article", collection: "History Quarterly",
            documentNumber: "123456", recordURL: "https://www.jstor.org/stable/123456"
        )
        let eric = Item(
            title: "ERIC report", documentType: "Reports - Research", collection: "ERIC",
            documentNumber: "ED123456", recordURL: "https://eric.ed.gov/?id=ED123456"
        )
        let pubmed = Item(
            title: "PubMed article", documentType: "Review", collection: "Medical Journal",
            documentNumber: "987654", recordURL: "https://pubmed.ncbi.nlm.nih.gov/987654/"
        )

        let tagged = ExportService.endNoteImport(items: [jstor, eric, pubmed])
        XCTAssertEqual(tagged.components(separatedBy: "%0 Journal Article").count - 1, 2)
        XCTAssertTrue(tagged.contains("%0 Report\n%T ERIC report"))
        XCTAssertTrue(tagged.contains("%J History Quarterly"))
        XCTAssertTrue(tagged.contains("%J Medical Journal"))
        XCTAssertTrue(tagged.contains("JSTOR Stable ID: 123456"))
        XCTAssertTrue(tagged.contains("ERIC Number: ED123456"))
        XCTAssertTrue(tagged.contains("PMID: 987654"))

        let xml = ExportService.endNoteXML(items: [jstor, eric, pubmed])
        XCTAssertEqual(xml.components(separatedBy: "<ref-type name=\"Journal Article\">17</ref-type>").count - 1, 2)
        XCTAssertTrue(xml.contains("<ref-type name=\"Report\">27</ref-type>"))
        XCTAssertTrue(xml.contains("<secondary-title><style face=\"normal\" font=\"default\" size=\"100%\">History Quarterly</style></secondary-title>"))
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
