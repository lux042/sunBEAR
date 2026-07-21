import Foundation

enum ExportService {
    // Preserve every CIA source field as a distinct column. Repeated names are
    // intentional: they map separate CIA values to the same EndNote field type.
    static let headers = [
        "Title",             // Title
        "Notes",             // Document Type
        "Notes",             // Collection
        "Notes",             // Document Number (FOIA) / ESDN (CREST)
        "Notes",             // Release Decision
        "Notes",             // Original Classification
        "Pages",             // Document Page Count
        "Notes",             // Document Creation Date
        "Notes",             // Document Release Date
        "Notes",             // Sequence Number
        "Date",              // Publication Date
        "Notes",             // Content Type
        "Notes",             // Case Number
        "URL",               // CIA Record URL
        "URL",               // PDF URL
        "Abstract"           // Body
    ]

    static func endNoteTSV(items: [Item]) -> String {
        // The *CIA reference-type marker belongs in the exported filename.
        tsv(items: items)
    }

    static func preservationTSV(items: [Item]) -> String { tsv(items: items) }

    private static func tsv(items: [Item]) -> String {
        ([headers.joined(separator: "\t")] + items.map { row($0) }).joined(separator: "\n") + "\n"
    }

    private static func row(_ item: Item) -> String {
        let pdfURLs = item.pdfURLs.filter { !$0.isEmpty }.joined(separator: " ")
        return [
            item.title,
            item.documentType,
            item.collection,
            item.documentNumber,
            item.releaseDecision,
            item.originalClassification,
            item.pageCount == 0 ? "" : String(item.pageCount),
            item.documentCreationDate,
            item.documentReleaseDate,
            item.sequenceNumber,
            item.publicationDate,
            item.contentType,
            item.caseNumber,
            item.recordURL,
            pdfURLs,
            item.body
        ]
            .map { clean($0) }.joined(separator: "\t")
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }
}
