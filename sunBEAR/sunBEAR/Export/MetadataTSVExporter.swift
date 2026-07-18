import Foundation

struct MetadataTSVExporter {
    enum ExportError: LocalizedError {
        case applicationSupportUnavailable

        var errorDescription: String? {
            "sunBEAR could not locate the Application Support folder."
        }
    }

    // These headings intentionally preserve the CIA metadata labels used by the
    // parser. Changing them would break repeatable EndNote import mappings.
    private let columns = [
        "Title",
        "Document Type",
        "Collection",
        "Document Number (FOIA) /ESDN (CREST)",
        "Release Decision",
        "Original Classification",
        "Document Page Count",
        "Document Creation Date",
        "Document Release Date",
        "Sequence Number",
        "Publication Date",
        "Content Type",
        "Case Number",
        "CIA Record URL",
        "PDF URL",
        "Body"
    ]

    func export(records: [CIADocumentRecord], jobID: UUID, displayName: String) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ExportError.applicationSupportUnavailable
        }

        let exportDirectory = applicationSupport
            .appendingPathComponent("sunBEAR", isDirectory: true)
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        let filename = "\(safeFilename(displayName))-metadata.tsv"
        let fileURL = exportDirectory.appendingPathComponent(filename)
        var rows = [columns.joined(separator: "\t")]
        rows.append(contentsOf: records.map(row(for:)))

        // A UTF-8 BOM helps EndNote and spreadsheet applications recognize the
        // file encoding consistently.
        let contents = "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func row(for record: CIADocumentRecord) -> String {
        let values: [String?] = [
            record.title,
            record.documentType,
            record.collection,
            record.documentNumber,
            record.releaseDecision,
            record.originalClassification,
            record.documentPageCount.map(String.init),
            record.documentCreationDate,
            record.documentReleaseDate,
            record.sequenceNumber,
            record.publicationDate,
            record.contentType,
            record.caseNumber,
            record.sourceURL.absoluteString,
            record.pdfURL?.absoluteString,
            record.body
        ]
        return values.map { sanitize($0 ?? "") }.joined(separator: "\t")
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted
        let cleaned = value.components(separatedBy: invalid).joined()
        return cleaned.replacingOccurrences(of: " ", with: "-").prefix(100).description
    }
}
