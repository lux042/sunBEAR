import Foundation

enum EBSCOHTMLParser {
    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        captures(#"(?is)<a[^>]+href\s*=\s*[\"']([^\"']+/(?:details|viewer)/[^\"']+)[\"']"#, in: html)
            .compactMap { normalizedURL($0, relativeTo: baseURL) }
            .filter { $0.host?.lowercased() == "research.ebsco.com" }
            .filter { !$0.path.localizedCaseInsensitiveContains("/pdfviewer/") }
            .map(removingTrackingFragment)
            .uniqued()
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        let current = Int(items.first(where: { $0.name == "p" })?.value ?? "1") ?? 1
        let next = current + 1
        let hasNext = html.range(of: #"(?:aria-label|title)\s*=\s*[\"'][^\"']*next"#, options: [.regularExpression, .caseInsensitive]) != nil
            || html.range(of: #"[?&](?:amp;)?p=#(next)(?:[&\"'])"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard hasNext else { return nil }
        items.removeAll { $0.name == "p" }
        items.append(URLQueryItem(name: "p", value: String(next)))
        components?.queryItems = items
        return components?.url
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        var result = ScrapedDocument(recordURL: url)
        result.title = firstMeta(["citation_title", "dc.title", "DC.Title"], in: html)
            ?? heading(in: html)
            ?? "Untitled"
        result.fields["Document Type"] = firstMeta(["citation_type", "dc.type", "DC.Type"], in: html) ?? labeled(["Source Type", "Publication Type"], in: html) ?? "EBSCO Record"
        result.fields["Collection"] = firstMeta(["citation_journal_title", "dc.source", "DC.Source", "citation_publisher"], in: html) ?? labeled(["Publication", "Source"], in: html) ?? "EBSCO"
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = recordIdentifier(in: html, url: url)
        let rawDate = firstMeta(["citation_publication_date", "citation_date", "dc.date", "DC.Date"], in: html) ?? ""
        result.fields["Publication Date"] = readableDate(rawDate)
        result.fields["Document Page Count"] = pageCount(in: html)
        result.fields["Content Type"] = "EBSCO"
        let abstractText = abstract(in: html)
            ?? labeled(["Abstract"], in: html)
            ?? firstMeta(["description", "dc.description", "DC.Description"], in: html)
            ?? ""
        let cleanedAbstract = plainText(abstractText)
        result.body = cleanedAbstract.caseInsensitiveCompare("Additional information") == .orderedSame ? "" : cleanedAbstract
        let explicitPDFs = captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+(?:\.pdf|/pdfviewer/|pdf=true)[^\"']*)[\"']"#, in: html)
        let labeledPDFs = downloadActions(in: html)
        result.pdfURLs = (explicitPDFs + labeledPDFs)
            .compactMap { normalizedURL($0, relativeTo: url) }
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
            .uniqued()
        result.externalURLs = externalFullTextLinks(in: html, baseURL: url)
        return result
    }

    private static func recordIdentifier(in html: String, url: URL) -> String {
        if let value = firstMeta(["citation_id", "dc.identifier", "DC.Identifier"], in: html), !value.isEmpty { return value }
        if let value = labeled(["Accession Number", "AN"], in: html), !value.isEmpty { return value }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let value = query.first(where: { ["an", "id", "recordid"].contains($0.name.lowercased()) })?.value { return value }
        return url.pathComponents.last(where: { !$0.isEmpty && $0 != "details" && $0 != "viewer" }) ?? ""
    }

    private static func pageCount(in html: String) -> String {
        guard let pages = firstMeta(["citation_firstpage"], in: html),
              let last = firstMeta(["citation_lastpage"], in: html),
              let firstNumber = Int(pages), let lastNumber = Int(last), lastNumber >= firstNumber else { return "" }
        return String(lastNumber - firstNumber + 1)
    }

    private static func externalFullTextLinks(in html: String, baseURL: URL) -> [URL] {
        anchors(in: html)
            .filter { anchor in
                anchor.label.range(of: #"(?:full\s*text|access\s+now|view\s+(?:article|record)|publisher|find\s+it|doi)"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
            .compactMap { anchor -> (URL, String)? in
                guard let link = normalizedURL(anchor.href, relativeTo: baseURL) else { return nil }
                return (link, anchor.label)
            }
            .filter { link, label in
                guard ["http", "https"].contains(link.scheme?.lowercased() ?? "") else { return false }
                let host = link.host?.lowercased() ?? ""
                let isEBSCOOnlineText = host == "research.ebsco.com"
                    && label.range(of: #"(?:online\s+full\s+text|access\s+now)"#, options: [.regularExpression, .caseInsensitive]) != nil
                return isEBSCOOnlineText || (host != "research.ebsco.com"
                    && !["legal.ebsco.com", "library.truman.edu"].contains(host))
            }
            .map(\.0)
            .uniqued()
    }

    private static func downloadActions(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<(a|button)([^>]*)>(.*?)</\1>"#) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 3 else { return nil }
            let attributes = ns.substring(with: match.range(at: 2))
            let label = plainText(ns.substring(with: match.range(at: 3)))
            let isDownload = label.range(of: #"^(?:pdf\s+full\s+text|download\s+pdf|view\s+pdf|pdf\s+download)$"#, options: [.regularExpression, .caseInsensitive]) != nil
            guard isDownload else { return nil }
            return captures(#"(?is)(?:href|formaction|data-(?:href|url|download-url))\s*=\s*[\"']([^\"']+)[\"']"#, in: attributes).first
        }
    }

    private static func anchors(in html: String) -> [(href: String, label: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a[^>]+href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            return (decode(ns.substring(with: match.range(at: 1))), plainText(ns.substring(with: match.range(at: 2))))
        }
    }

    private static func labeled(_ labels: [String], in html: String) -> String? {
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            if let value = captures(#"(?is)(?:<[^>]+>\s*)?"# + escaped + #"\s*:?(?:\s*</[^>]+>)*\s*<[^>]+>(.*?)</[^>]+>"#, in: html).first.map(plainText), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func readableDate(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 8,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.suffix(2)),
              (1...12).contains(month), (1...31).contains(day) else { return value }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        guard let date = components.date else { return value }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private static func heading(in html: String) -> String? {
        captures(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: html).first.map(plainText)
    }

    private static func abstract(in html: String) -> String? {
        captures(#"(?is)<(?:section|div)[^>]*(?:id|class)\s*=\s*[\"'][^\"']*abstract[^\"']*[\"'][^>]*>(.*?)</(?:section|div)>"#, in: html).first.map(plainText)
    }

    private static func firstMeta(_ names: [String], in html: String) -> String? {
        names.compactMap { meta($0, in: html) }.first { !$0.isEmpty }
    }

    private static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return captures(#"(?is)<meta(?=[^>]*(?:name|property)\s*=\s*[\"']"# + escaped + #"[\"'])[^>]*content\s*=\s*[\"']([^\"']*)[\"']"#, in: html).first.map(decode)
    }

    private static func normalizedURL(_ value: String, relativeTo baseURL: URL) -> URL? {
        guard let url = URL(string: decode(value), relativeTo: baseURL)?.absoluteURL else { return nil }
        guard url.host?.lowercased() == "research.ebsco.com", url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }

    private static func removingTrackingFragment(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url ?? url
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
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func captures(_ pattern: String, in value: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > group ? ns.substring(with: $0.range(at: group)) : nil
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
