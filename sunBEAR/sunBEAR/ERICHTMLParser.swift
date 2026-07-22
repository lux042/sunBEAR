import Foundation

enum ERICHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)<a[^>]+href\s*=\s*[\"']([^\"']*[?&](?:amp;)?id=(?:EJ|ED)\d+[^\"']*)[\"']"#, in: html)
            .compactMap { value -> URL? in
                guard let url = URL(string: decode(value), relativeTo: baseURL)?.absoluteURL,
                      url.host?.lowercased() == "eric.ed.gov" else { return nil }
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard let identifier = items.first(where: { $0.name == "id" })?.value else { return nil }
                var components = URLComponents(string: "https://eric.ed.gov/")!
                components.queryItems = [URLQueryItem(name: "id", value: identifier)]
                return components.url
            }
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        guard let href = captures(#"(?is)<a[^>]+href\s*=\s*[\"']([^\"']*[?&](?:amp;)?pg=\d+[^\"']*)[\"'][^>]*>\s*Next Page"#, in: html).first else { return nil }
        return URL(string: decode(href), relativeTo: baseURL)?.absoluteURL
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        var result = ScrapedDocument(recordURL: url)
        result.title = (meta("citation_title", in: html) ?? text(in: html, className: "title") ?? "Untitled")
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
            .trimmed

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let identifier = meta("citation_technical_report_number", in: html)
            ?? query.first(where: { $0.name == "id" })?.value
            ?? labeled("ERIC Number", in: html)
            ?? ""
        result.fields["Document Type"] = labeled("Record Type", in: html) ?? "ERIC Record"
        result.fields["Collection"] = meta("citation_journal_title", in: html) ?? "ERIC"
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = identifier
        result.fields["Publication Date"] = meta("citation_publication_date", in: html) ?? labeled("Publication Date", in: html) ?? ""
        result.fields["Document Page Count"] = labeled("Pages", in: html) ?? ""
        result.fields["Content Type"] = "ERIC"
        result.body = plainText(meta("citation_abstract", in: html) ?? meta("description", in: html) ?? "")
        result.pdfURLs = captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+\.pdf(?:\?[^\"']*)?)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: url)?.absoluteURL }
            .filter { $0.host?.lowercased() == "files.eric.ed.gov" }
            .uniqued()
        return result
    }

    private static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let value = captures(#"(?is)<meta(?=[^>]*name\s*=\s*[\"']"# + escaped + #"[\"'])[^>]*content\s*=\s*[\"']([^\"']*)[\"']"#, in: html).first else { return nil }
        return decode(value)
    }

    private static func labeled(_ label: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: label)
        return captures(#"(?is)<strong>\s*"# + escaped + #":?\s*</strong>\s*([^<]+)"#, in: html).first.map { plainText($0) }
    }

    private static func text(in html: String, className: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: className)
        return captures(#"(?is)<div[^>]*class\s*=\s*[\"']"# + escaped + #"[\"'][^>]*>(.*?)</div>"#, in: html).first.map { plainText($0) }
    }

    private static func plainText(_ value: String) -> String {
        decode(value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&hellip;", with: "…")
    }

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
