import Foundation
import SwiftData

@Model
final class SavedCIADocument {
    var id: UUID
    var sourceURLString: String
    var title: String
    var documentType: String?
    var collection: String?
    var documentNumber: String?
    var releaseDecision: String?
    var originalClassification: String?
    var documentPageCount: Int?
    var documentCreationDate: String?
    var documentReleaseDate: String?
    var sequenceNumber: String?
    var publicationDate: String?
    var contentType: String?
    var caseNumber: String?
    var body: String?
    var pdfURLString: String?
    var localPDFPath: String?
    var rawMetadataJSON: Data
    var job: ScrapeJob?

    init(record: CIADocumentRecord, job: ScrapeJob? = nil) {
        id = UUID()
        sourceURLString = record.sourceURL.absoluteString
        title = record.title
        documentType = record.documentType
        collection = record.collection
        documentNumber = record.documentNumber
        releaseDecision = record.releaseDecision
        originalClassification = record.originalClassification
        documentPageCount = record.documentPageCount
        documentCreationDate = record.documentCreationDate
        documentReleaseDate = record.documentReleaseDate
        sequenceNumber = record.sequenceNumber
        publicationDate = record.publicationDate
        contentType = record.contentType
        caseNumber = record.caseNumber
        body = record.body
        pdfURLString = record.pdfURL?.absoluteString
        rawMetadataJSON = (try? JSONEncoder().encode(record.rawMetadata)) ?? Data()
        self.job = job
    }

    var sourceURL: URL? { URL(string: sourceURLString) }
    var pdfURL: URL? { pdfURLString.flatMap(URL.init(string:)) }

    var rawMetadata: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: rawMetadataJSON)) ?? [:]
    }
}
