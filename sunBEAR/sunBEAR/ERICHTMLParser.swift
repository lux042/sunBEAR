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
        let publicationDate = meta("citation_publication_date", in: html) ?? labeled("Publication Date", in: html) ?? ""
        result.fields["Publication Date"] = readablePublicationDate(publicationDate)
        result.fields["Document Page Count"] = labeled("Pages", in: html) ?? ""
        result.fields["Content Type"] = "ERIC"
        result.body = plainText(meta("citation_abstract", in: html) ?? meta("description", in: html) ?? "")
        result.pdfURLs = captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+\.pdf(?:\?[^\"']*)?)[\"']"#, in: html)
            .compactMap { URL(string: decode($0), relativeTo: url)?.absoluteURL }
            .filter { $0.host?.lowercased() == "files.eric.ed.gov" }
            .map { pdfURL in
                var components = URLComponents(url: pdfURL, resolvingAgainstBaseURL: false)
                components?.scheme = "https"
                return components?.url ?? pdfURL
            }
            .uniqued()
        result.externalURLs = externalResourceLinks(in: html, baseURL: url)
        return result
    }

    private static func externalResourceLinks(in html: String, baseURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<a([^>]*)href\s*=\s*[\"']([^\"']+)[\"']([^>]*)>(.*?)</a>"#
        ) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges == 5 else { return nil }
            let attributes = ns.substring(with: match.range(at: 1)) + " " + ns.substring(with: match.range(at: 3))
            let href = decode(ns.substring(with: match.range(at: 2)))
            let label = plainText(ns.substring(with: match.range(at: 4)))
            let hint = (attributes + " " + label).lowercased()
            guard let link = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  ["http", "https"].contains(link.scheme?.lowercased() ?? ""),
                  link.host?.lowercased().hasSuffix("eric.ed.gov") != true else { return nil }
            let host = link.host?.lowercased() ?? ""
            let isRelevant = host == "doi.org"
                || hint.range(of: #"full\s*text|publisher|available\s+from|external\s+link|institutional\s+repository|view\s+article|view\s+record|doi"#, options: .regularExpression) != nil
            guard isRelevant,
                  !["facebook.com", "twitter.com", "x.com", "linkedin.com"].contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
            return link
        }.uniqued()
    }

    private static func readablePublicationDate(_ value: String) -> String {
        let parts = value.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month) || month == 0 else { return value }

        if month == 0 { return String(year) }
        let monthName = Calendar.current.monthSymbols[month - 1]
        if day == 0 { return "\(monthName) \(year)" }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else { return value }
        return date.formatted(.dateTime.month(.wide).day().year())
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
