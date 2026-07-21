import Foundation

struct ScrapedDocument: Sendable {
    var title = "Untitled"
    var fields: [String: String] = [:]
    var recordURL: URL
    var pdfURLs: [URL] = []
    var body = ""
}

enum CIAHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        links(in: html, baseURL: baseURL)
            .filter {
                $0.path.contains("/readingroom/document/") ||
                $0.path.contains("/readingroom/document-view/")
            }
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"(?is)<a(?=[^>]*\brel\s*=\s*[\"']next[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<a(?=[^>]*(?:title|aria-label)\s*=\s*[\"'][^\"']*next[^\"']*[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<li(?=[^>]*class\s*=\s*[\"'][^\"']*(?:pager__item--next|pager-next)[^\"']*[\"'])[^>]*>.*?<a[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<a[^>]+href\s*=\s*[\"']([^\"']+)[\"'][^>]*>\s*(?:<[^>]+>\s*)*(?:Next|Next\s*›|›)"#
        ]
        for pattern in patterns {
            if let href = firstCapture(pattern, in: html), let url = URL(string: decode(href), relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }
        return nil
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        let text = plainText(html)
        var result = ScrapedDocument(recordURL: url)

        let labels = ["Document Type", "Collection", "Document Number (FOIA) /ESDN (CREST)", "Release Decision", "Original Classification", "Document Page Count", "Document Creation Date", "Document Release Date", "Sequence Number", "Publication Date", "Content Type", "Case Number"]
        let anyLabel = labels.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        for label in labels {
            // CIA's classic pages do not always display fields in the same order.
            // Stop at whichever known field comes next rather than assuming an order.
            let pattern = "(?is)" + NSRegularExpression.escapedPattern(for: label) + #"\s*:\s*(.*?)\s*(?=(?:"# + anyLabel + #")\s*:|File\s*:|Body\s*:|$)"#
            result.fields[label] = firstCapture(pattern, in: text)?.trimmed ?? ""
        }

        // The first <h1> on these pages is often the site heading "Library".
        // The actual record title is the final text line before Document Type.
        if let fieldStart = text.range(of: "Document Type:", options: .caseInsensitive) {
            let candidates = text[..<fieldStart.lowerBound].components(separatedBy: .newlines)
                .map(\.trimmed).filter { !$0.isEmpty }
            result.title = candidates.last ?? "Untitled"
        } else {
            let headings = captures(#"(?is)<h[1-6][^>]*>(.*?)</h[1-6]>"#, in: html).map { plainText($0) }
            result.title = headings.last(where: { $0.caseInsensitiveCompare("Library") != .orderedSame }) ?? "Untitled"
        }
        if let range = text.range(of: "Body:", options: .caseInsensitive) {
            var body = String(text[range.upperBound...]).trimmed
            if let printer = body.range(of: "Printer-friendly version", options: .caseInsensitive) {
                body = String(body[..<printer.lowerBound]).trimmed
            }
            result.body = body
        }
        result.pdfURLs = links(in: html, baseURL: url).filter { $0.pathExtension.lowercased() == "pdf" }.uniqued()
        return result
    }

    private static func links(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)href\s*=\s*[\"']([^\"']+)[\"']"#, in: html).compactMap {
            URL(string: decode($0), relativeTo: baseURL)?.absoluteURL
        }
    }

    private static func plainText(_ html: String) -> String {
        decode(html
            .replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</h[1-6]>|</li>|</tr>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
            .trimmed
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? { captures(pattern, in: value).first }

    private static func captures(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
