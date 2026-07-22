import Foundation

enum JSTORHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)<(?:a|[a-z0-9-]+)(?=[^>]*(?:data-qa\s*=\s*[\"']search-result-title-link[\"']|href\s*=\s*[\"'][^\"']*/stable/))[^>]*href\s*=\s*[\"']([^\"']*/stable/[^\"']+)[\"']"#, in: html)
            .compactMap { cleanStableURL($0, relativeTo: baseURL) }
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"(?is)<(?:a|[a-z0-9-]+)(?=[^>]*\brel\s*=\s*[\"']next[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<(?:a|[a-z0-9-]+)(?=[^>]*data-qa\s*=\s*[\"'][^\"']*(?:pagination-next|next-page)[^\"']*[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<(?:a|[a-z0-9-]+)(?=[^>]*(?:aria-label|title)\s*=\s*[\"'][^\"']*next[^\"']*[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#
        ]
        for pattern in patterns {
            if let href = captures(pattern, in: html).first,
               let url = URL(string: decode(href), relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }
        return nil
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        var result = ScrapedDocument(recordURL: url)
        let title = meta("citation_title", in: html) ?? meta("og:title", in: html) ?? heading(in: html)
        result.title = (title ?? "Untitled").replacingOccurrences(of: #"\s*\|\s*JSTOR\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmed

        let stableID = url.path.components(separatedBy: "/stable/").last?.components(separatedBy: "?").first ?? ""
        result.fields["Document Type"] = meta("citation_type", in: html) ?? attribute("data-itemtype", in: html) ?? "JSTOR Item"
        result.fields["Collection"] = meta("citation_journal_title", in: html) ?? meta("citation_book_title", in: html) ?? meta("citation_publisher", in: html) ?? "JSTOR"
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = stableID
        result.fields["Publication Date"] = meta("citation_publication_date", in: html) ?? meta("citation_date", in: html) ?? ""
        result.fields["Content Type"] = "JSTOR"

        let description = meta("description", in: html) ?? meta("og:description", in: html) ?? ""
        result.body = plainText(description)
        result.pdfURLs = captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: url)?.absoluteURL }
            .filter { $0.path.contains("/stable/pdf/") || $0.pathExtension.lowercased() == "pdf" }
            .uniqued()
        if !stableID.isEmpty,
           let downloadablePDF = URL(string: "/stable/pdf/\(stableID).pdf", relativeTo: url)?.absoluteURL,
           !result.pdfURLs.contains(downloadablePDF) {
            result.pdfURLs.append(downloadablePDF)
        }
        return result
    }

    private static func cleanStableURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard let url = URL(string: decode(value), relativeTo: baseURL)?.absoluteURL,
              url.host?.lowercased().hasSuffix("jstor.org") == true else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url
    }

    private static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"(?is)<meta(?=[^>]*(?:name|property)\s*=\s*[\"']"# + escaped + #"[\"'])[^>]*content\s*=\s*[\"']([^\"']*)[\"']"#,
            #"(?is)<meta(?=[^>]*content\s*=\s*[\"']([^\"']*)[\"'])[^>]*(?:name|property)\s*=\s*[\"']"# + escaped + #"[\"'][^>]*>"#
        ]
        guard let value = patterns.compactMap({ captures($0, in: html).first }).first else { return nil }
        return decode(value)
    }

    private static func attribute(_ name: String, in html: String) -> String? {
        guard let value = captures("(?is)" + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*[\"']([^\"']+)[\"']"#, in: html).first else { return nil }
        return decode(value)
    }

    private static func heading(in html: String) -> String? {
        guard let value = captures(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html).first else { return nil }
        return plainText(value)
    }

    private static func plainText(_ html: String) -> String {
        decode(html.replacingOccurrences(of: #"(?is)<script.*?</script>|<style.*?</style>|<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
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
