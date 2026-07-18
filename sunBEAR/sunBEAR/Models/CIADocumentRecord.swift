import Foundation

struct CIADocumentRecord: Identifiable, Hashable, Sendable {
    var id: URL { sourceURL }

    let sourceURL: URL
    let title: String

    let documentType: String?
    let collection: String?
    let documentNumber: String?
    let releaseDecision: String?
    let originalClassification: String?
    let documentPageCount: Int?

    let documentCreationDate: String?
    let documentReleaseDate: String?
    let sequenceNumber: String?
    let publicationDate: String?

    let contentType: String?
    let caseNumber: String?
    let body: String?
    let pdfURL: URL?

    let rawMetadata: [String: String]
}
