import Foundation
import WebKit

/// Loads CIA pages through WebKit because the Reading Room redirects non-browser
/// HTTP clients away from advanced-search results. The same session is retained
/// for pagination and document pages so cookies are preserved.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<(html: String, finalURL: URL), Error>?
    private var requestedURL: URL?

    override init() {
        let configuration = WKWebViewConfiguration()
        // Share the visible search browser's cookies/session with the scraper.
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    }

    func html(at url: URL) async throws -> (html: String, finalURL: URL) {
        guard continuation == nil else { throw LoaderError.alreadyLoading }
        requestedURL = url
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // CIA result rows can be populated shortly after the navigation finishes.
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            do {
                let value = try await webView.evaluateJavaScript("document.documentElement.outerHTML")
                guard let html = value as? String, let finalURL = webView.url else { throw LoaderError.noHTML }
                finish(.success((html, finalURL)))
            } catch {
                finish(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<(html: String, finalURL: URL), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        requestedURL = nil
        continuation.resume(with: result)
    }

    enum LoaderError: LocalizedError {
        case alreadyLoading
        case noHTML

        var errorDescription: String? {
            switch self {
            case .alreadyLoading: "A CIA page is already loading."
            case .noHTML: "The CIA page loaded without readable HTML."
            }
        }
    }
}
