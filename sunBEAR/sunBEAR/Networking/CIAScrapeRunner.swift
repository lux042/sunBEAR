import Foundation

struct CIAScrapeProgress: Sendable {
    let pagesCompleted: Int
    let documentsDiscovered: Int
    let documentsParsed: Int
}

struct CIAScrapeRunResult: Sendable {
    let pagesCompleted: Int
    let records: [CIADocumentRecord]
}

struct CIAScrapeRunner: Sendable {
    enum RunnerError: LocalizedError {
        case invalidSearchURL
        case noDocumentLinks

        var errorDescription: String? {
            switch self {
            case .invalidSearchURL:
                "The CIA search URL could not be created."
            case .noDocumentLinks:
                "The CIA page returned no document links. The Reading Room may be redirecting or temporarily unavailable; no metadata was generated."
            }
        }
    }

    private let client = CIAHTTPClient()
    private let requestBuilder = CIASearchRequestBuilder()
    private let resultParser = CIASearchResultParser()
    private let documentParser = CIADocumentParser()

    // The Reading Room is a public service, not a bulk API. These intentionally
    // conservative delays keep requests serial and avoid synchronized bursts.
    private let documentDelayRange = 2.5...5.0
    private let pageDelayRange = 8.0...15.0
    private let maximumAttempts = 4

    func run(
        query: CIASearchQuery,
        progress: @escaping @Sendable (CIAScrapeProgress) async -> Void
    ) async throws -> CIAScrapeRunResult {
        guard var pageURL = requestBuilder.makeURL(for: query) else {
            throw RunnerError.invalidSearchURL
        }

        var pagesCompleted = 0
        var discoveredURLs = Set<URL>()
        var records: [CIADocumentRecord] = []
        var documentRequests = 0

        while pagesCompleted < query.maximumPages {
            try Task.checkCancellation()
            let html = try await fetchWithBackoff(from: pageURL)
            let page = resultParser.parsePage(html: html, baseURL: pageURL)
            if pagesCompleted == 0 && page.results.isEmpty {
                throw RunnerError.noDocumentLinks
            }
            pagesCompleted += 1

            let newResults = page.results.filter {
                discoveredURLs.insert($0.documentURL).inserted
            }
            await progress(
                CIAScrapeProgress(
                    pagesCompleted: pagesCompleted,
                    documentsDiscovered: discoveredURLs.count,
                    documentsParsed: records.count
                )
            )

            for result in newResults {
                guard documentRequests < query.maximumDocumentRequests else {
                    return CIAScrapeRunResult(
                        pagesCompleted: pagesCompleted,
                        records: records
                    )
                }
                try Task.checkCancellation()
                try await sleepRandomly(in: documentDelayRange)
                documentRequests += 1
                let detailHTML = try await fetchWithBackoff(from: result.documentURL)
                if let record = documentParser.parse(
                    html: detailHTML,
                    sourceURL: result.documentURL
                ) {
                    records.append(record)
                    await progress(
                        CIAScrapeProgress(
                            pagesCompleted: pagesCompleted,
                            documentsDiscovered: discoveredURLs.count,
                            documentsParsed: records.count
                        )
                    )
                }
            }

            guard let nextPageURL = page.nextPageURL else { break }
            pageURL = nextPageURL
            if pagesCompleted < query.maximumPages {
                try await sleepRandomly(in: pageDelayRange)
            }
        }

        return CIAScrapeRunResult(
            pagesCompleted: pagesCompleted,
            records: records
        )
    }

    private func fetchWithBackoff(from url: URL) async throws -> String {
        var attempt = 1

        while true {
            try Task.checkCancellation()
            do {
                return try await client.fetchHTML(from: url)
            } catch CIAHTTPClient.ClientError.httpStatus(let status, let retryAfter)
                where Self.isRetryable(status) && attempt < maximumAttempts {
                let exponentialDelay = min(120.0, 5.0 * pow(2.0, Double(attempt - 1)))
                let serverDelay = retryAfter ?? 0
                let jitter = Double.random(in: 0.75...2.5)
                try await Task.sleep(for: .seconds(max(serverDelay, exponentialDelay) + jitter))
                attempt += 1
            } catch let error as URLError
                where Self.isRetryable(error) && attempt < maximumAttempts {
                let delay = min(120.0, 5.0 * pow(2.0, Double(attempt - 1)))
                try await Task.sleep(for: .seconds(delay + Double.random(in: 0.75...2.5)))
                attempt += 1
            }
        }
    }

    private func sleepRandomly(in range: ClosedRange<Double>) async throws {
        try await Task.sleep(for: .seconds(Double.random(in: range)))
    }

    private static func isRetryable(_ status: Int) -> Bool {
        status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    }

    private static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            true
        default:
            false
        }
    }
}
