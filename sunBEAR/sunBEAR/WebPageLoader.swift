import Foundation
import WebKit

/// Loads source pages through WebKit so JavaScript-rendered search results and
/// the user's CIA/JSTOR session cookies remain available to the scraper.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<(html: String, finalURL: URL), Error>?
    private var requestedURL: URL?
    private var downloadContinuation: CheckedContinuation<URL?, Error>?
    private var downloadDestination: URL?

    init(webView existingWebView: WKWebView? = nil) {
        if let existingWebView {
            // NYT imports must use the exact browser instance in which the user
            // signed in. A second WKWebView can temporarily see stale cookies.
            webView = existingWebView
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            webView = WKWebView(frame: .zero, configuration: configuration)
        }
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

    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
    }

    /// EBSCO exposes full text through a two-step JavaScript dialog rather than
    /// a stable PDF link. Drive that dialog in the authenticated web view and
    /// let WebKit hand the resulting attachment to us directly.
    func downloadEBSCOFullText(to folder: URL, baseName: String) async throws -> URL? {
        guard downloadContinuation == nil else { throw LoaderError.alreadyDownloading }
        let openDialogScript = #"""
        (() => {
          const visible = element => !!(element && element.getClientRects().length);
          const text = element => (element?.innerText || element?.textContent || '').trim();
          const initial = Array.from(document.querySelectorAll('button, a')).find(element =>
            visible(element) && /^download$/i.test(text(element)) && !element.closest('[role="dialog"], dialog'));
          if (!initial) return false;
          initial.click();
          return true;
        })()
        """#
        guard try await webView.evaluateJavaScript(openDialogScript) as? Bool == true else { return nil }
        try await Task.sleep(for: .milliseconds(700))

        let selectFormatScript = #"""
        (() => {
          const visible = element => !!(element && element.getClientRects().length);
          const text = element => (element?.innerText || element?.textContent || '').trim();
          const dialog = Array.from(document.querySelectorAll('[role="dialog"], dialog')).find(visible);
          if (!dialog) return '';
          const labels = Array.from(dialog.querySelectorAll('label'));
          const pdfLabel = labels.find(label => /^pdf(?:\s|$)/i.test(text(label)));
          const pdfInput = pdfLabel?.querySelector('input') || Array.from(dialog.querySelectorAll('input[type="radio"]')).find(input => {
            const label = input.labels?.[0]; return label && /^pdf(?:\s|$)/i.test(text(label));
          });
          if (pdfInput) {
            pdfInput.click();
            return 'pdf';
          }
          const htmlLabel = labels.find(label => /online\s+full\s+text\s*\(html\)/i.test(text(label)));
          const htmlInput = htmlLabel?.querySelector('input') || Array.from(dialog.querySelectorAll('input[type="radio"]')).find(input => {
            const label = input.labels?.[0]; return label && /online\s+full\s+text\s*\(html\)/i.test(text(label));
          });
          if (htmlInput) {
            htmlInput.click();
            return 'html';
          }
          return '';
        })()
        """#
        guard let selectedFormat = try await webView.evaluateJavaScript(selectFormatScript) as? String,
              ["pdf", "html"].contains(selectedFormat) else { return nil }

        let target = uniqueDownloadURL(folder.appendingPathComponent(baseName).appendingPathExtension(selectedFormat))
        downloadDestination = target
        return try await withCheckedThrowingContinuation { continuation in
            downloadContinuation = continuation
            let confirmScript = #"""
            (() => {
              const visible = element => !!(element && element.getClientRects().length);
              const dialog = Array.from(document.querySelectorAll('[role="dialog"], dialog')).find(visible);
              const confirm = Array.from(dialog?.querySelectorAll('button, a') || []).find(element =>
                visible(element) && /^download$/i.test((element.innerText || element.textContent || '').trim()));
              if (!confirm) return false;
              confirm.click();
              return true;
            })()
            """#
            webView.evaluateJavaScript(confirmScript) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.finishDownload(.failure(error))
                    return
                }
                guard value as? Bool == true else {
                    self.finishDownload(.success(nil))
                    return
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, self.downloadContinuation != nil else { return }
                    self.finishDownload(.failure(LoaderError.downloadTimedOut))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Both sources populate portions of their result pages after navigation.
        Task {
            let host = webView.url?.host?.lowercased() ?? ""
            let isNYT = host.hasSuffix("nytimes.com")
            let isEBSCO = host == "research.ebsco.com"
            try? await Task.sleep(for: isNYT || isEBSCO ? .milliseconds(1_500) : .milliseconds(750))
            if isNYT {
                _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight)")
                try? await Task.sleep(for: .milliseconds(1_000))
            }
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

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard downloadContinuation != nil else {
            decisionHandler(.allow)
            return
        }
        let response = navigationResponse.response
        let mime = response.mimeType?.lowercased() ?? ""
        let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if mime == "application/pdf" || disposition.contains("attachment") {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        completionHandler(downloadDestination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestination else {
            finishDownload(.failure(LoaderError.noDownloadDestination))
            return
        }
        finishDownload(.success(destination))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finishDownload(.failure(error))
    }

    private func finish(_ result: Result<(html: String, finalURL: URL), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        requestedURL = nil
        continuation.resume(with: result)
    }

    private func finishDownload(_ result: Result<URL?, Error>) {
        guard let continuation = downloadContinuation else { return }
        downloadContinuation = nil
        downloadDestination = nil
        continuation.resume(with: result)
    }

    private func uniqueDownloadURL(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            var candidate = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(number)")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    enum LoaderError: LocalizedError {
        case alreadyLoading
        case alreadyDownloading
        case downloadTimedOut
        case noDownloadDestination
        case noHTML

        var errorDescription: String? {
            switch self {
            case .alreadyLoading: "A source page is already loading."
            case .alreadyDownloading: "An EBSCO download is already in progress."
            case .downloadTimedOut: "EBSCO did not start the full-text download within 30 seconds."
            case .noDownloadDestination: "EBSCO started a download without a usable destination."
            case .noHTML: "The source page loaded without readable HTML."
            }
        }
    }
}
