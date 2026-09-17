import Foundation
import PDFKit
import NaturalLanguage

enum ArchivalPDFExtractor {
    struct Result {
        var title: String
        var documentNumber: String
        var publicationDate: String
        var originalClassification: String
        var pageCount: Int
        var abstract: String
        var keywords: String
        var caseNumber: String
    }

    struct DocumentResult {
        var title: String
        var documentType: String
        var collection: String
        var documentNumber: String
        var releaseDecision: String
        var originalClassification: String
        var pageIndexes: [Int]
        var documentCreationDate: String
        var documentReleaseDate: String
        var sequenceNumber: String
        var publicationDate: String
        var contentType: String
        var caseNumber: String
        var abstract: String
        var keywords: String
    }

    struct DocumentExtraction {
        var bundleTitle: String
        var documents: [DocumentResult]
    }

    static func extractDocuments(from url: URL) throws -> DocumentExtraction {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadablePDF }
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ExtractionError.noText
        }

        let fileTitle = meaningfulFilenameTitle(url)
        let coverTitle = folderTitle(in: pages.first ?? "")
        let bundleTitle = archivalTitle(filename: fileTitle, cover: coverTitle)
        let caseNumber = firstMatch(#"(?m)^\s*(\d{3}(?:\.\d+)?)\s+[A-Z]"#, in: pages.first ?? "")?
            .replacingOccurrences(of: #"\s+[A-Z].*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var groups: [[Int]] = []
        for index in pages.indices {
            let text = pages[index]
            if index == 0, looksLikeFolderCover(text) { continue }
            if isDocumentStart(text) || groups.isEmpty { groups.append([index]) }
            else { groups[groups.count - 1].append(index) }
        }

        let results = groups.compactMap { indexes -> DocumentResult? in
            let text = indexes.map { pages[$0] }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let type = documentType(in: text)
            let number = normalizedDocumentNumber(in: text)
            let dates = unique(matches(#"(?i)\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b"#, in: text))
            let date = dates.first ?? ""
            let classifications = ["SECRET", "CONFIDENTIAL", "UNCLASSIFIED"].filter {
                text.range(of: #"\b"# + $0 + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
            let keywordList = keywords(in: text)
            let title = documentTitle(type: type, number: number, text: text, keywords: keywordList)
            return DocumentResult(
                title: title,
                documentType: type,
                collection: bundleTitle,
                documentNumber: number,
                releaseDecision: text.localizedCaseInsensitiveContains("declassified") ? "Declassified" : "",
                originalClassification: classifications.joined(separator: "; "),
                pageIndexes: indexes,
                documentCreationDate: date,
                documentReleaseDate: "",
                sequenceNumber: "",
                publicationDate: date,
                contentType: "Department of State archival record",
                caseNumber: caseNumber,
                abstract: documentDescription(type: type, number: number, date: date, keywords: keywordList, pageCount: indexes.count),
                keywords: keywordList.joined(separator: "; ")
            )
        }
        return DocumentExtraction(bundleTitle: bundleTitle, documents: results)
    }

    static func writePages(_ indexes: [Int], from sourceURL: URL, to destinationURL: URL) throws {
        guard let source = PDFDocument(url: sourceURL) else { throw ExtractionError.unreadablePDF }
        let output = PDFDocument()
        for index in indexes {
            if let page = source.page(at: index)?.copy() as? PDFPage { output.insert(page, at: output.pageCount) }
        }
        guard output.pageCount > 0, output.write(to: destinationURL) else { throw ExtractionError.unreadablePDF }
    }

    static func extract(from url: URL) throws -> Result {
        guard let document = PDFDocument(url: url) else { throw ExtractionError.unreadablePDF }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
        let text = pages.joined(separator: "\n")
            .replacingOccurrences(of: "\u{0C}", with: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noText
        }

        let fileTitle = meaningfulFilenameTitle(url)
        let coverTitle = folderTitle(in: pages.first ?? "")
        let title = archivalTitle(filename: fileTitle, cover: coverTitle)
        let labeledNumbers = matches(#"(?i)\bNO\.?\s*:?[ \t]*([A-Z]{1,5}[-–]?[ \t]*\d{1,7})\b"#, in: text)
            .map { $0.replacingOccurrences(of: #"(?i)^NO\.?\s*:?\s*"#, with: "", options: .regularExpression).replacingOccurrences(of: " ", with: "") }
        let numbers = unique(labeledNumbers)
        let dates = unique(matches(#"(?i)\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}\b"#, in: text))
        let classifications = ["SECRET", "CONFIDENTIAL", "UNCLASSIFIED"].filter { text.range(of: #"\b"# + $0 + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let classification = classifications.joined(separator: "; ")
        let keywordList = keywords(in: text)
        let description = draftDescription(title: title, dates: dates, keywords: keywordList, pageCount: document.pageCount)
        let folderDate = yearRange(in: title)
        let caseNumber = firstMatch(#"(?m)^\s*(\d{3}(?:\.\d+)?)\s+[A-Z]"#, in: pages.first ?? "")?
            .replacingOccurrences(of: #"\s+[A-Z].*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return Result(
            title: title,
            documentNumber: numbers.prefix(6).joined(separator: "; "),
            publicationDate: folderDate.isEmpty ? (dates.first ?? "") : folderDate,
            originalClassification: classification,
            pageCount: document.pageCount,
            abstract: description,
            keywords: keywordList.joined(separator: "; "),
            caseNumber: caseNumber
        )
    }

    private static func folderTitle(in firstPage: String) -> String? {
        let lines = firstPage.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.localizedCaseInsensitiveContains("declassified") && !$0.localizedCaseInsensitiveContains("authority") }
        guard let candidate = lines.first(where: { $0.range(of: #"[A-Za-z]{3,}.*(?:19|20)\d{2}"#, options: .regularExpression) != nil }) else { return nil }
        let cleaned = candidate.replacingOccurrences(of: #"^[\d.'\s]+"#, with: "", options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned.capitalized
    }

    private static func meaningfulFilenameTitle(_ url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"^\s*\d+[._ -]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stem.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil else { return nil }
        return stem.capitalized
    }

    private static func archivalTitle(filename: String?, cover: String?) -> String {
        let year = cover.map { yearRange(in: $0) } ?? ""
        if let filename, !filename.isEmpty {
            return year.isEmpty ? filename : "\(filename), \(expandedYearRange(year))"
        }
        return cover ?? "Untitled archival PDF"
    }

    private static func expandedYearRange(_ value: String) -> String {
        guard let match = value.range(of: #"^((?:19|20)\d{2})(?:[-–]\d{2,4})+$"#, options: .regularExpression) else { return value }
        let parts = value[match].split(whereSeparator: { $0 == "-" || $0 == "–" })
        guard let first = parts.first, let last = parts.last, parts.count >= 2 else { return value }
        let expandedLast = last.count == 2 ? "\(first.prefix(2))\(last)" : String(last)
        return "\(first)–\(expandedLast)"
    }

    private static func yearRange(in value: String) -> String {
        matches(#"\b(?:19|20)\d{2}(?:[-–](?:\d{2}|(?:19|20)\d{2})){1,2}\b"#, in: value).first ?? ""
    }

    private static func draftDescription(title: String, dates: [String], keywords: [String], pageCount: Int) -> String {
        var result = "Draft machine-generated description — review before EndNote export. Archival PDF bundle titled \"\(title)\" containing \(pageCount) pages"
        if !dates.isEmpty { result += ", with documents dated \(dates.prefix(4).joined(separator: ", "))" }
        if !keywords.isEmpty { result += ". Recurring subjects include \(keywords.prefix(8).joined(separator: ", "))" }
        return result + "."
    }

    private static func looksLikeFolderCover(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("declassified") &&
        !text.localizedCaseInsensitiveContains("telegram") &&
        !text.localizedCaseInsensitiveContains("airgram")
    }

    private static func isDocumentStart(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("AIRGRAM") || upper.contains("TELEGRAM") ||
            (upper.contains("FOREIGN SERVICE") && (upper.contains("INCOMING") || upper.contains("OUTGOING")))
    }

    private static func documentType(in text: String) -> String {
        let upper = text.uppercased()
        if upper.contains("AIRGRAM") { return "Airgram / Circular" }
        if upper.contains("OUTGOING") { return "Outgoing telegram" }
        if upper.contains("INCOMING") || upper.contains("TELEGRAM") { return "Incoming telegram" }
        return "Archival document"
    }

    private static func normalizedDocumentNumber(in text: String) -> String {
        guard let value = firstMatch(#"(?i)\bNO\.?\s*:?[ \t]*([A-Z]{0,5}[-–]?[ \t]*\d{1,7})\b"#, in: text) else { return "" }
        return value.replacingOccurrences(of: #"(?i)^NO\.?\s*:?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "–", with: "-")
    }

    private static func documentTitle(type: String, number: String, text: String, keywords: [String]) -> String {
        if let subject = firstMatch(#"(?im)^\s*(?:SUBJECT|SUBJ)\s*:?\s*[^\n]{8,140}"#, in: text) {
            let cleaned = subject.replacingOccurrences(of: #"(?i)^\s*(?:SUBJECT|SUBJ)\s*:?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        let topic = keywords.prefix(4).map { $0.capitalized }.joined(separator: ", ")
        let identifier = number.isEmpty ? "" : " " + number
        return topic.isEmpty ? type + identifier : type + identifier + ": " + topic
    }

    private static func documentDescription(type: String, number: String, date: String, keywords: [String], pageCount: Int) -> String {
        var value = "Draft machine-generated description — review before EndNote export. " + type
        if !number.isEmpty { value += " " + number }
        if !date.isEmpty { value += ", dated " + date }
        value += ", consisting of " + String(pageCount) + " page" + (pageCount == 1 ? "" : "s")
        if !keywords.isEmpty { value += ". Subjects include " + keywords.prefix(8).joined(separator: ", ") }
        return value + "."
    }

    private static func keywords(in text: String) -> [String] {
        let stop = Set(["this", "that", "with", "from", "have", "were", "would", "which", "their", "there", "been", "they", "department", "copy", "page", "pages", "information", "united", "states", "foreign", "service", "classification", "declassified", "authority", "organization", "action", "america", "authorized", "government", "governments", "message", "representative", "additional", "requested"])
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var counts: [String: Int] = [:]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count >= 5, word.range(of: #"^[a-z][a-z'-]+$"#, options: .regularExpression) != nil, !stop.contains(word) {
                counts[word, default: 0] += 1
            }
            return true
        }
        return counts.sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            .prefix(12).map(\.key)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? { matches(pattern, in: text).first }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    enum ExtractionError: LocalizedError {
        case unreadablePDF, noText
        var errorDescription: String? {
            switch self {
            case .unreadablePDF: "The PDF could not be opened."
            case .noText: "No searchable text was found in the PDF. OCR is required before it can be imported."
            }
        }
    }
}
