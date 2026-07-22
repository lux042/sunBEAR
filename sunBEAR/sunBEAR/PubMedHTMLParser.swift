import Foundation

enum PubMedHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)<a(?=[^>]*class\s*=\s*[\"'][^\"']*docsum-title)[^>]*href\s*=\s*[\"'](/\d+/)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: baseURL)?.absoluteURL }
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        guard html.localizedCaseInsensitiveContains("next-page-btn") || html.contains("data-next-page-url") else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        let current = Int(items.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
        items.removeAll { $0.name == "page" }
        items.append(URLQueryItem(name: "page", value: String(current + 1)))
        components?.queryItems = items
        return components?.url
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        var result = ScrapedDocument(recordURL: url)
        result.title = (meta("citation_title", in: html) ?? heading(in: html) ?? "Untitled").trimmed
        let pmid = meta("citation_pmid", in: html) ?? url.pathComponents.first(where: { Int($0) != nil }) ?? ""
        result.fields["Document Type"] = publicationType(in: html) ?? "PubMed Citation"
        result.fields["Collection"] = meta("citation_journal_title", in: html) ?? meta("citation_publisher", in: html) ?? "PubMed"
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = pmid
        result.fields["Publication Date"] = meta("citation_date", in: html) ?? ""
        result.fields["Content Type"] = "PubMed"
        result.body = abstract(in: html)
        result.pdfURLs = pdfURLs(in: html, baseURL: url)
        return result
    }

    static func pmcArticleURL(in html: String, baseURL: URL) -> URL? {
        captures(#"(?is)href\s*=\s*[\"'](https://pmc\.ncbi\.nlm\.nih\.gov/articles/(?:PMC\d+|pmid/\d+)/?)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: baseURL)?.absoluteURL }
            .first
    }

    static func pdfURLs(in html: String, baseURL: URL) -> [URL] {
        let patterns = [
            #"(?is)<meta(?=[^>]*name\s*=\s*[\"']citation_pdf_url[\"'])[^>]*content\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)href\s*=\s*[\"']([^\"']*/pdf/[^\"']+\.pdf(?:\?[^\"']*)?)[\"']"#
        ]
        return patterns.flatMap { captures($0, in: html) }
            .compactMap { URL(string: decode($0), relativeTo: baseURL)?.absoluteURL }
            .filter { $0.host?.lowercased() == "pmc.ncbi.nlm.nih.gov" }
            .uniqued()
    }

    private static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let value = captures(#"(?is)<meta(?=[^>]*name\s*=\s*[\"']"# + escaped + #"[\"'])[^>]*content\s*=\s*[\"']([^\"']*)[\"']"#, in: html).first else { return nil }
        return decode(value)
    }

    private static func heading(in html: String) -> String? {
        guard let value = captures(#"(?is)<h1[^>]*class\s*=\s*[\"'][^\"']*heading-title[^\"']*[\"'][^>]*>(.*?)</h1>"#, in: html).first else { return nil }
        return plainText(value)
    }

    private static func publicationType(in html: String) -> String? {
        guard let value = captures(#"(?is)<span[^>]*class\s*=\s*[\"'][^\"']*publication-type[^\"']*[\"'][^>]*>(.*?)</span>"#, in: html).first else { return nil }
        return plainText(value)
    }

    private static func abstract(in html: String) -> String {
        guard let value = captures(#"(?is)<div[^>]*class\s*=\s*[\"'][^\"']*abstract-content\s+selected[^\"']*[\"'][^>]*>(.*?)</div>"#, in: html).first else { return "" }
        return plainText(value)
    }

    private static func plainText(_ value: String) -> String {
        decode(value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmed
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
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
