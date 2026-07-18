import Foundation

struct CIAHTTPClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, retryAfter: TimeInterval?)
        case invalidTextEncoding

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "The CIA server returned an invalid response."
            case .httpStatus(let status, _): "The CIA server returned HTTP status \(status)."
            case .invalidTextEncoding: "The CIA page was not valid UTF-8 text."
            }
        }
    }

    func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(
            "sunBEAR/1.0 academic archival research application",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw ClientError.httpStatus(
                response.statusCode,
                retryAfter: Self.retryDelay(from: response)
            )
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ClientError.invalidTextEncoding
        }
        return html
    }

    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        if let seconds = TimeInterval(value) {
            return max(0, seconds)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
