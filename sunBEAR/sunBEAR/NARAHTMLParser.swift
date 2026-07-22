import Foundation

enum NARAHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)<a[^>]+href\s*=\s*[\"'](/id/\d+)(?:\?[^\"']*)?[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: baseURL)?.absoluteURL }
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        let current = Int(items.first(where: { $0.name == "page" })?.value ?? "1") ?? 1
        let next = current + 1
        guard html.range(of: "Go to page \(next)", options: .caseInsensitive) != nil
                || html.range(of: #"aria-label=[\"']Go to page \#(next)[\"']"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        items.removeAll { $0.name == "page" }
        items.append(URLQueryItem(name: "page", value: String(next)))
        components?.queryItems = items
        return components?.url
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        var result = ScrapedDocument(recordURL: url)
        result.title = heading(in: html) ?? "Untitled"
        let naid = captures(#"(?is)NAID:\s*</?[^>]*>?\s*(\d+)"#, in: html).first
            ?? url.pathComponents.first(where: { Int($0) != nil }) ?? ""
        result.fields["Document Type"] = firstText(#"(?is)<(?:div|span)[^>]*>\s*(Item|File Unit|Series|Collection|Record Group)\s*</(?:div|span)>"#, in: html) ?? "National Archives Record"
        result.fields["Collection"] = collection(in: html) ?? "National Archives Catalog"
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = naid
        result.fields["Publication Date"] = date(in: html)
        result.fields["Content Type"] = "National Archives"
        result.body = description(in: html)
        result.pdfURLs = captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+\.pdf(?:\?[^\"']*)?)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: url)?.absoluteURL }
            .filter { $0.host?.lowercased() == "catalog.archives.gov" }
            .uniqued()
        return result
    }

    private static func heading(in html: String) -> String? {
        firstText(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html)
    }

    private static func collection(in html: String) -> String? {
        firstText(#"(?is)(?:Record Group(?:\s+\d+)?|Collection)\s*</[^>]+>\s*<(?:h2|div|span)[^>]*>(.*?)</(?:h2|div|span)>"#, in: html)
    }

    private static func date(in html: String) -> String {
        firstText(#"(?is)<h2[^>]*>\s*Dates[^<]*</h2>\s*.*?((?:January|February|March|April|May|June|July|August|September|October|November|December)[^<]{3,100})"#, in: html) ?? ""
    }

    private static func description(in html: String) -> String {
        firstText(#"(?is)<(?:h2|h3)[^>]*>\s*(?:Scope and Content|Description)[^<]*</(?:h2|h3)>\s*(?:<[^>]+>\s*)*(.*?)</(?:p|div)>"#, in: html) ?? ""
    }

    private static func firstText(_ pattern: String, in html: String) -> String? {
        guard let captured = captures(pattern, in: html).first else { return nil }
        let text = plainText(captured)
        return text.isEmpty ? nil : text
    }

    private static func plainText(_ value: String) -> String {
        decode(value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
    }

    private static func captures(_ pattern: String, in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
