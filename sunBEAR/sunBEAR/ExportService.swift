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
        tsv(items: items)
    }

    static func preservationTSV(items: [Item]) -> String { tsv(items: items) }

    /// EndNote's tagged import format. Opening this file in EndNote invokes its
    /// built-in "EndNote Import" filter, avoiding a manual TSV import setup.
    static func endNoteImport(items: [Item]) -> String {
        items.map { item in
            // The receiving EndNote installation defines a custom reference
            // type named "CIA" with these standard tagged fields enabled.
            var fields = ["%0 CIA", "%T \(tagValue(item.title))"]
            appendNotes(for: item, to: &fields)
            if item.pageCount > 0 { fields.append("%P \(item.pageCount)") }
            appendTagged("%8", value: item.publicationDate, to: &fields)
            // EndNote opens the first URL as the record's primary link. CIA's
            // metadata pages sometimes redirect to the Reading Room homepage,
            // so prefer the stable direct PDF while retaining the record page.
            for url in item.pdfURLs { appendTagged("%U", value: url, to: &fields) }
            appendTagged("%U", value: item.recordURL, to: &fields)
            appendTagged("%X", value: item.body, to: &fields)
            for path in item.localPDFPaths { appendTagged("%>", value: path, to: &fields) }
            return fields.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

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

    private static func tagValue(_ value: String) -> String { clean(value).trimmingCharacters(in: .whitespaces) }

    private static func appendTagged(_ tag: String, value: String, to fields: inout [String]) {
        let value = tagValue(value)
        if !value.isEmpty { fields.append("\(tag) \(value)") }
    }

    private static func appendNotes(for item: Item, to fields: inout [String]) {
        let values = [
            ("Document Type", item.documentType),
            ("Collection", item.collection),
            ("Document Number (FOIA) / ESDN (CREST)", item.documentNumber),
            ("Release Decision", item.releaseDecision),
            ("Original Classification", item.originalClassification),
            ("Document Creation Date", item.documentCreationDate),
            ("Document Release Date", item.documentReleaseDate),
            ("Sequence Number", item.sequenceNumber),
            ("Content Type", item.contentType),
            ("Case Number", item.caseNumber)
        ]
        let notes = values.compactMap { label, rawValue -> String? in
            let value = tagValue(rawValue)
            return value.isEmpty ? nil : "\(label): \(value)"
        }.joined(separator: " | ")
        appendTagged("%Z", value: notes, to: &fields)
    }
}
