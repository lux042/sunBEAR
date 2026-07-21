import Foundation
import SwiftData

@Model
final class Item {
    var title: String
    var documentType: String
    var collection: String
    var documentNumber: String
    var releaseDecision: String
    var originalClassification: String
    var pageCount: Int
    var documentCreationDate: String
    var documentReleaseDate: String
    var sequenceNumber: String
    var publicationDate: String
    var contentType: String
    var caseNumber: String
    var recordURL: String
    var pdfURLs: [String]
    var body: String
    var localPDFPaths: [String]
    var downloadError: String
    var scrapedAt: Date
    var session: ScrapeSession?

    init(
        title: String,
        documentType: String = "",
        collection: String = "",
        documentNumber: String = "",
        releaseDecision: String = "",
        originalClassification: String = "",
        pageCount: Int = 0,
        documentCreationDate: String = "",
        documentReleaseDate: String = "",
        sequenceNumber: String = "",
        publicationDate: String = "",
        contentType: String = "",
        caseNumber: String = "",
        recordURL: String,
        pdfURLs: [String] = [],
        body: String = "",
        localPDFPaths: [String] = [],
        downloadError: String = "",
        scrapedAt: Date = .now,
        session: ScrapeSession? = nil
    ) {
        self.title = title
        self.documentType = documentType
        self.collection = collection
        self.documentNumber = documentNumber
        self.releaseDecision = releaseDecision
        self.originalClassification = originalClassification
        self.pageCount = pageCount
        self.documentCreationDate = documentCreationDate
        self.documentReleaseDate = documentReleaseDate
        self.sequenceNumber = sequenceNumber
        self.publicationDate = publicationDate
        self.contentType = contentType
        self.caseNumber = caseNumber
        self.recordURL = recordURL
        self.pdfURLs = pdfURLs
        self.body = body
        self.localPDFPaths = localPDFPaths
        self.downloadError = downloadError
        self.scrapedAt = scrapedAt
        self.session = session
    }
}
