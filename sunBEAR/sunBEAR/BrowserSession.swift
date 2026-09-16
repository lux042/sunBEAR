import WebKit
import Observation

/// Owns the visible browser for the lifetime of the main window. Keeping one
/// WKWebView avoids presenting users with separate NYT login contexts.
@MainActor
@Observable
final class BrowserSession {
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    }
}
