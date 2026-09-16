import Foundation

enum NewYorkTimesHTMLParser {
    static func isArticle(_ url: URL) -> Bool {
        guard isNYTHost(url) else { return false }
        if url.host?.lowercased() == "timesmachine.nytimes.com" {
            return matches(#"^/timesmachine/\d{4}/\d{2}/\d{2}/\d+\.html$"#, url.path)
        }
        return matches(#"^/(?:\d{4}/\d{2}/\d{2}/|(?:aponline|reuters)/\d{4}/\d{2}/\d{2}/).+\.html$"#, url.path)
            || (url.path.lowercased() == "/gst/abstract.html" && query(url)["res"]?.isEmpty == false)
    }

    static func isSearch(_ url: URL) -> Bool {
        guard isNYTHost(url) else { return false }
        if url.path.lowercased().hasPrefix("/topic/") { return true }
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path == "search" || (url.host?.lowercased() == "timesmachine.nytimes.com" && path == "browser") else { return false }
        let values = query(url)
        return ["query", "q", "search"].contains { values[$0]?.isEmpty == false }
    }

    static func canonical(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if url.path.lowercased() == "/gst/abstract.html", let value = query(url)["res"] {
            components?.queryItems = [URLQueryItem(name: "res", value: value)]
        } else {
            components?.query = nil
        }
        return components?.url ?? url
    }

    static func resultLinks(in html: String, baseURL: URL) -> [URL] {
        let searchTerms = Set((query(baseURL)["query"] ?? query(baseURL)["q"] ?? query(baseURL)["search"] ?? "")
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let wantsGames = !searchTerms.isDisjoint(with: ["crossword", "crosswords", "game", "games", "puzzle", "puzzles"])
        var seen = Set<URL>()
        return captures(#"(?is)<a[^>]+href\s*=\s*[\"']([^\"']+)[\"']"#, html).compactMap {
            URL(string: decode($0), relativeTo: baseURL)?.absoluteURL
        }.filter(isArticle).filter { url in
            wantsGames || !["/crosswords/", "/games/", "/puzzles/"].contains { url.path.lowercased().contains($0) }
        }.map(canonical).filter { seen.insert($0).inserted }
    }

    static func nextPage(in html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"(?is)<a(?=[^>]*\brel\s*=\s*[\"']next[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
            #"(?is)<a(?=[^>]*(?:aria-label|title)\s*=\s*[\"'][^\"']*next[^\"']*[\"'])[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern, html), let url = URL(string: decode(value), relativeTo: baseURL)?.absoluteURL, isSearch(url) {
                return url
            }
        }
        return nil
    }

    static func document(from html: String, url: URL) -> ScrapedDocument {
        let jsonObjects = captures(#"(?is)<script[^>]+type\s*=\s*[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#, html)
            .compactMap { $0.data(using: .utf8) }
            .compactMap { try? JSONSerialization.jsonObject(with: $0) }
            .flatMap(articleObjects)
        let article = jsonObjects.first { object in
            let raw = object["@type"]
            let types = raw as? [String] ?? (raw as? String).map { [$0] } ?? []
            return !Set(types).isDisjoint(with: ["NewsArticle", "Article", "ReportageNewsArticle", "OpinionNewsArticle"])
        }
        let canonicalURL = metaLink("canonical", html: html).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        let recordURL = canonicalURL.map { isArticle($0) ? canonical($0) : canonical(url) } ?? canonical(url)
        var result = ScrapedDocument(recordURL: recordURL)
        let headline = string(article?["headline"]) ?? meta(["citation_title", "og:title", "DC.title"], html: html) ?? firstCapture(#"(?is)<h1[^>]*>(.*?)</h1>"#, html) ?? "Untitled"
        result.title = flat(headline).replacingOccurrences(of: #"\s*[-|–]\s*(?:The )?New York Times\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let fullArticle = articleText(in: html, structuredArticle: article)
        result.body = fullArticle.isEmpty
            ? flat(string(article?["description"]) ?? meta(["description", "og:description", "DC.description"], html: html) ?? "")
            : fullArticle
        result.fields["Document Type"] = "Newspaper Article"
        result.fields["Collection"] = "The New York Times"
        var publicationDate = string(article?["datePublished"]) ?? meta(["article:published_time", "date", "pdate", "pubdate", "citation_publication_date", "DC.date"], html: html) ?? ""
        if publicationDate.isEmpty, let date = firstCapture(#"/(\d{4}/\d{2}/\d{2})/"#, url.path) { publicationDate = date.replacingOccurrences(of: "/", with: "-") }
        if matches(#"^\d{8}$"#, publicationDate) {
            publicationDate = "\(publicationDate.prefix(4))-\(publicationDate.dropFirst(4).prefix(2))-\(publicationDate.suffix(2))"
        }
        result.fields["Publication Date"] = publicationDate
        result.fields["Document Number (FOIA) /ESDN (CREST)"] = meta(["articleid", "article_id", "nyt_uri"], html: html)
            ?? string(article?["identifier"])
            ?? query(url)["res"]
            ?? (url.host?.lowercased() == "timesmachine.nytimes.com" ? url.deletingPathExtension().lastPathComponent : "")
        result.fields["Content Type"] = url.host?.lowercased() == "timesmachine.nytimes.com" ? "TimesMachine archive" : "NYT article"
        result.pdfURLs = publisherPDFLinks(in: html, baseURL: url)
        return result
    }

    static func readableArticlePage(from html: String, document: ScrapedDocument, capturedAt: Date = .now) throws -> String {
        let blocks = articleBlocks(in: html)
        guard !blocks.isEmpty else { throw ArticlePageError.noReadableText }
        let formatter = ISO8601DateFormatter()
        let title = escapeHTML(document.title)
        let source = escapeHTML(document.recordURL.absoluteString)
        let date = escapeHTML(document.fields["Publication Date"] ?? "")
        let article = blocks.map { "<p>\(escapeHTML($0))</p>" }.joined(separator: "\n")
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(title)</title><style>body{font:18px/1.65 Georgia,serif;max-width:760px;margin:3rem auto;padding:0 1.5rem;color:#17251f}header{border-bottom:1px solid #ccd8d0;margin-bottom:2rem}h1{line-height:1.15}a{color:#17613f}footer{border-top:1px solid #ccd8d0;margin-top:2rem;padding-top:1rem;color:#596c63;font:14px/1.5 system-ui}</style></head>
        <body><header><h1>\(title)</h1><p>The New York Times\(date.isEmpty ? "" : " · \(date)")</p><p><a href="\(source)">Open original article</a></p></header>
        <main>\(article)</main><footer>Saved by sunBEAR on \(escapeHTML(formatter.string(from: capturedAt))). Readable text from the article displayed in your signed-in browser session; images and interactive elements are not included.</footer></body></html>
        """
    }

    private static func articleText(in html: String, structuredArticle: [String: Any]?) -> String {
        let blocks = articleBlocks(in: html)
        if !blocks.isEmpty { return blocks.joined(separator: "\n\n") }
        return flat(string(structuredArticle?["articleBody"]) ?? "")
    }

    private static func articleBlocks(in html: String) -> [String] {
        // Current NYT pages identify story paragraphs directly. Capturing these
        // first avoids navigation, recommendations, and unrelated page modules.
        var raw = captures(#"(?is)<(?:h2|h3|p|blockquote)(?=[^>]*data-testid\s*=\s*[\"'](?:paragraph|article-body|story-body)[\"'])[^>]*>(.*?)</(?:h2|h3|p|blockquote)>"#, html)

        // Archive and alternate layouts wrap the complete story in a semantic
        // section/article. Match those containers (not arbitrary nested divs),
        // then preserve every readable block in its original order.
        if raw.isEmpty {
            let roots = captures(#"(?is)<(?:section|article)[^>]*(?:name\s*=\s*[\"']articleBody[\"']|data-testid\s*=\s*[\"']article-body[\"']|itemprop\s*=\s*[\"']articleBody[\"'])[^>]*>(.*?)</(?:section|article)>"#, html)
            raw = roots.flatMap {
                captures(#"(?is)<(?:h2|h3|p|blockquote)[^>]*>(.*?)</(?:h2|h3|p|blockquote)>"#, $0)
            }
        }

        var seen = Set<String>()
        return raw.map(flat).filter { text in
            guard text.count >= 2 else { return false }
            let boilerplate = text.lowercased()
            guard !boilerplate.contains("subscribe to the times"),
                  !boilerplate.contains("already a subscriber?"),
                  !boilerplate.contains("thanks for reading the times") else { return false }
            return seen.insert(text).inserted
        }
    }

    private static func publisherPDFLinks(in html: String, baseURL: URL) -> [URL] {
        var seen = Set<URL>()
        return captures(#"(?is)(?:href|content)\s*=\s*[\"']([^\"']+)[\"']"#, html).compactMap {
            URL(string: decode($0), relativeTo: baseURL)?.absoluteURL
        }.filter { url in
            guard isNYTHost(url) else { return false }
            return url.pathExtension.lowercased() == "pdf"
                || (url.host?.lowercased() == "timesmachine.nytimes.com" && url.path == "/svc/tmach/v1/refer" && query(url)["pdf"]?.lowercased() == "true")
        }.filter { seen.insert($0).inserted }
    }

    private static func isNYTHost(_ url: URL) -> Bool {
        guard url.scheme == "https" || url.scheme == "http", let host = url.host?.lowercased() else { return false }
        return host == "nytimes.com" || host.hasSuffix(".nytimes.com")
    }

    private static func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") })
    }

    private static func articleObjects(_ value: Any) -> [[String: Any]] {
        if let array = value as? [Any] { return array.flatMap(articleObjects) }
        guard let object = value as? [String: Any] else { return [] }
        return [object] + ((object["@graph"] as? [Any])?.flatMap(articleObjects) ?? [])
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func meta(_ names: [String], html: String) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"(?is)<meta(?=[^>]*(?:name|property)\s*=\s*[\"']"# + escaped + #"[\"'])[^>]*content\s*=\s*[\"']([^\"']*)[\"']"#,
                #"(?is)<meta(?=[^>]*content\s*=\s*[\"']([^\"']*)[\"'])[^>]*(?:name|property)\s*=\s*[\"']"# + escaped + #"[\"']"#
            ]
            for pattern in patterns where firstCapture(pattern, html)?.isEmpty == false { return decode(firstCapture(pattern, html)!) }
        }
        return nil
    }

    private static func metaLink(_ relation: String, html: String) -> String? {
        firstCapture(#"(?is)<link(?=[^>]*rel\s*=\s*[\"']"# + NSRegularExpression.escapedPattern(for: relation) + #"[\"'])[^>]*href\s*=\s*[\"']([^\"']+)[\"']"#, html).map(decode)
    }

    private static func flat(_ html: String) -> String {
        decode(html.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func firstCapture(_ pattern: String, _ value: String) -> String? { captures(pattern, value).first }
    private static func captures(_ pattern: String, _ value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = value as NSString
        return regex.matches(in: value, range: NSRange(location: 0, length: ns.length)).compactMap {
            $0.numberOfRanges > 1 && $0.range(at: 1).location != NSNotFound ? ns.substring(with: $0.range(at: 1)) : nil
        }
    }
}

private enum ArticlePageError: LocalizedError {
    case noReadableText
    var errorDescription: String? {
        "No readable article body was available. Use NYT sign in, confirm that the article is visible in sunBEAR, and try again."
    }
}
