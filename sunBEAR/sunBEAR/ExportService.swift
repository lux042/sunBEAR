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

    /// EndNote's AppleScript interface accepts RSXML directly. This avoids the
    /// automatic `.enw` importer, which cannot select a user's custom filter.
    static func endNoteXML(items: [Item]) -> String {
        let records = items.map { item in
            let reference = endNoteReference(for: item)
            let relatedURLs = (item.pdfURLs + [item.recordURL]).filter { !$0.isEmpty }.map {
                "<url>\(xmlStyle($0))</url>"
            }.joined()
            let attachments = item.localPDFPaths.filter { !$0.isEmpty }.map {
                "<url>\(xml(URL(fileURLWithPath: $0).absoluteString))</url>"
            }.joined()
            return """
            <record>
            <ref-type name="\(reference.name)">\(reference.number)</ref-type>
            <titles><title>\(xmlStyle(item.title))</title>\(item.collection.isEmpty ? "" : "<secondary-title>\(xmlStyle(item.collection))</secondary-title>")</titles>
            \(item.pageCount > 0 ? "<pages>\(xmlStyle(String(item.pageCount)))</pages>" : "")
            \(item.publicationDate.isEmpty ? "" : "<dates><pub-dates><date>\(xmlStyle(item.publicationDate))</date></pub-dates></dates>")
            \(item.body.isEmpty ? "" : "<abstract>\(xmlStyle(item.body))</abstract>")
            \(notesValue(for: item).isEmpty ? "" : "<notes>\(xmlStyle(notesValue(for: item)))</notes>")
            \(relatedURLs.isEmpty ? "" : "<urls><related-urls>\(relatedURLs)</related-urls>\(attachments.isEmpty ? "" : "<pdf-urls>\(attachments)</pdf-urls>")</urls>")
            </record>
            """
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" ?><xml><records>\(records)</records></xml>"
    }

    /// EndNote's tagged import format. Opening this file in EndNote invokes its
    /// built-in "EndNote Import" filter, avoiding a manual TSV import setup.
    static func endNoteImport(items: [Item]) -> String {
        items.map { item in
            let reference = endNoteReference(for: item)
            var fields = ["%0 \(reference.name)", "%T \(tagValue(item.title))"]
            if reference.name != "CIA" { appendTagged("%J", value: item.collection, to: &fields) }
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
        appendTagged("%Z", value: notesValue(for: item), to: &fields)
    }

    private static func notesValue(for item: Item) -> String {
        let source = source(for: item)
        let values = [
            ("Document Type", item.documentType),
            ("Collection", item.collection),
            (identifierLabel(for: source), item.documentNumber),
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
        return notes
    }

    private static func source(for item: Item) -> ScrapeSource {
        guard let url = URL(string: item.recordURL), let source = ScrapeSource.source(for: url) else {
            // Older CIA records and tests may contain redirected or placeholder
            // URLs, so retain the app's original CIA behavior when unknown.
            return .cia
        }
        return source
    }

    private static func identifierLabel(for source: ScrapeSource) -> String {
        switch source {
        case .cia: "Document Number (FOIA) / ESDN (CREST)"
        case .jstor: "JSTOR Stable ID"
        case .eric: "ERIC Number"
        case .pubmed: "PMID"
        case .nara: "National Archives Identifier (NAID)"
        }
    }

    private static func endNoteReference(for item: Item) -> (name: String, number: Int) {
        let type = item.documentType.lowercased()
        switch source(for: item) {
        case .cia:
            return ("CIA", 40)
        case .pubmed:
            return ("Journal Article", 17)
        case .jstor:
            if type.contains("book") { return ("Book", 6) }
            if type.contains("report") { return ("Report", 27) }
            return ("Journal Article", 17)
        case .eric:
            if type.contains("journal") { return ("Journal Article", 17) }
            if type.contains("report") { return ("Report", 27) }
            if type.contains("book") { return ("Book", 6) }
            return ("Generic", 13)
        case .nara:
            return ("Generic", 13)
        }
    }

    private static func xmlStyle(_ value: String) -> String {
        "<style face=\"normal\" font=\"default\" size=\"100%\">\(xml(value))</style>"
    }

    private static func xml(_ value: String) -> String {
        // OCR extracted from PDFs can contain form feeds and other C0 control
        // characters. XML 1.0 rejects them, which can make EndNote silently
        // create a reference containing only the fields before the bad byte.
        let validXML = String(value.unicodeScalars.filter { scalar in
            let code = scalar.value
            return code == 0x09 || code == 0x0A || code == 0x0D ||
                (0x20...0xD7FF).contains(code) ||
                (0xE000...0xFFFD).contains(code) ||
                (0x10000...0x10FFFF).contains(code)
        })
        return validXML.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
