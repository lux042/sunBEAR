import SwiftUI
import WebKit

struct SearchBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var browserMessage = ""
    @State private var isPreparingImport = false
    @State private var nytSignedIn: Bool?
    let webView: WKWebView
    let source: ScrapeSource
    let initialURL: URL?
    let pageCount: Int
    let onImport: (URL, String?) -> Void

    init(webView: WKWebView, source: ScrapeSource, initialURL: URL? = nil, pageCount: Int = 1, onImport: @escaping (URL, String?) -> Void) {
        self.webView = webView
        self.source = source
        self.initialURL = initialURL
        self.pageCount = pageCount
        self.onImport = onImport
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                Button { webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Text(currentURL?.absoluteString ?? source.title)
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                if source == .jstor || source == .pubmed {
                    Button("Prepare PDF Downloads") { preparePDFDownloads() }
                        .help(source == .jstor
                              ? "Open a JSTOR PDF in this window so you can accept JSTOR's download terms once"
                              : "Open a PubMed Central PDF in this window so PMC can prepare the download session")
                }
                Button("Close") { dismiss() }
                Button(importButtonTitle) {
                    if source == .nyt, nytSignedIn == false {
                        webView.load(URLRequest(url: URL(string: "https://myaccount.nytimes.com/auth/login")!))
                        browserMessage = "Sign in here. After NYT returns you to the site, run your search and import it from this same window."
                    } else {
                        Task { await importVisiblePage() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparingImport || !canImportCurrentPage)
            }
            .padding(10)
            if !browserMessage.isEmpty {
                Text(browserMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            if source == .nyt && browserMessage.isEmpty {
                Text("Search or sign in here, then import the visible results. This browser keeps the same NYT session each time you open it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            Divider()
            SearchWebView(webView: webView, source: source, initialURL: initialURL, currentURL: $currentURL, canGoBack: $canGoBack, canGoForward: $canGoForward, nytSignedIn: $nytSignedIn)
        }
        .frame(minWidth: 980, minHeight: 700)
    }

    private var importButtonTitle: String {
        if source == .nyt, nytSignedIn == false { return "Sign in to import" }
        return source == .nyt ? "Import This Search" : "Import This \(source.title) Search"
    }

    private var canImportCurrentPage: Bool {
        guard let currentURL else { return false }
        if source != .nyt { return source.canImport(currentURL) }
        let host = currentURL.host?.lowercased() ?? ""
        let path = currentURL.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // NYT sometimes renders completed search results at /search while
        // keeping the query only in the page's search field.
        return host.hasSuffix("nytimes.com") && path == "search"
            || source.canImport(currentURL)
    }

    @MainActor private func importVisiblePage() async {
        guard let currentURL else { return }
        isPreparingImport = true
        browserMessage = source == .nyt ? "Preparing the visible NYT results for import…" : "Preparing this page for import…"
        if source == .nyt, NewYorkTimesHTMLParser.isSearch(currentURL) {
            for batch in 1..<max(1, pageCount) {
                browserMessage = "Loading NYT result batch \(batch + 1) of \(pageCount)…"
                _ = try? await evaluate(Self.expandNYTResultsScript)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        let isNYTSearchPage = source == .nyt && currentURL.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "search"
        let snapshotScript = isNYTSearchPage
            ? "document.querySelector('[data-testid=search-results]')?.outerHTML || document.querySelector('main')?.outerHTML || document.documentElement.outerHTML"
            : "document.documentElement.outerHTML"
        let html = try? await evaluate(snapshotScript) as? String
        guard let visibleURL = webView.url,
              isSameImportContext(currentURL, visibleURL) else {
            browserMessage = "The page changed while preparing the import. Check the NYT page and try again."
            isPreparingImport = false
            return
        }
        var importURL = visibleURL
        if isNYTSearchPage, !NewYorkTimesHTMLParser.isSearch(visibleURL) {
            let queryScript = #"""
            (() => {
              const candidates = Array.from(document.querySelectorAll('input[type="search"], input[name="query"], input[name="q"], input[aria-label*="search" i]'));
              return candidates.map(input => (input.value || '').trim()).find(Boolean) || '';
            })()
            """#
            if let searchText = try? await evaluate(queryScript) as? String,
               !searchText.isEmpty,
               var components = URLComponents(url: visibleURL, resolvingAgainstBaseURL: false) {
                components.queryItems = [URLQueryItem(name: "query", value: searchText)]
                importURL = components.url ?? visibleURL
            }
        }
        guard source.canImport(importURL) else {
            browserMessage = "Enter a New York Times search term, wait for the results to appear, then try again."
            isPreparingImport = false
            return
        }
        onImport(importURL, html ?? nil)
        dismiss()
    }

    private func isSameImportContext(_ original: URL, _ visible: URL) -> Bool {
        if source == .nyt {
            let originalPath = original.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let visiblePath = visible.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return original.host?.lowercased().hasSuffix("nytimes.com") == true
                && visible.host?.lowercased().hasSuffix("nytimes.com") == true
                && originalPath == "search" && visiblePath == "search"
        }
        return original == visible
    }

    @MainActor private func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private static let expandNYTResultsScript = #"""
    (() => {
      const root = document.querySelector('main') || document;
      const button = Array.from(root.querySelectorAll('button')).find(b =>
        !b.disabled && b.getAttribute('aria-disabled') !== 'true' && b.getClientRects().length > 0 &&
        /^(show more|load more|show more articles|load more articles|show more results|load more results)$/i.test((b.innerText || b.textContent || '').trim()));
      if (button) { button.click(); return 'clicked'; }
      window.scrollTo(0, document.documentElement.scrollHeight); return 'scrolled';
    })()
    """#

    private func preparePDFDownloads() {
        switch source {
        case .jstor: prepareJSTORPDFDownload()
        case .pubmed: preparePubMedPDFDownload()
        default: break
        }
    }

    private func prepareJSTORPDFDownload() {
        browserMessage = "Finding an article to open…"
        let script = #"""
        (() => {
          const current = location.pathname.match(/^\/stable\/(?!pdf\/)([^/?#]+)/);
          if (current) return current[1];
          const link = Array.from(document.querySelectorAll('a[href*="/stable/"]'))
            .map(a => a.href).find(href => !href.includes('/stable/pdf/'));
          return link ? new URL(link).pathname.match(/^\/stable\/([^/?#]+)/)?.[1] || null : null;
        })()
        """#
        webView.evaluateJavaScript(script) { value, _ in
            DispatchQueue.main.async {
                guard let stableID = value as? String,
                      let encodedID = stableID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let pdfURL = URL(string: "https://www.jstor.org/stable/pdf/\(encodedID).pdf") else {
                    browserMessage = "Open an article from the results, then choose Prepare PDF Downloads again."
                    return
                }
                browserMessage = "If JSTOR shows its download terms, review and accept them here. After the PDF appears, go Back and import the search."
                webView.load(URLRequest(url: pdfURL))
            }
        }
    }

    private func preparePubMedPDFDownload() {
        browserMessage = "Finding a PubMed Central article to open…"
        let script = #"""
        (() => {
          const metaPDF = document.querySelector('meta[name="citation_pdf_url"]')?.content;
          if (metaPDF && metaPDF.includes('pmc.ncbi.nlm.nih.gov/')) return metaPDF;
          const pmcLink = Array.from(document.querySelectorAll('a[href*="pmc.ncbi.nlm.nih.gov/articles/"]'))
            .map(a => a.href).find(Boolean);
          if (!pmcLink) return null;
          const match = new URL(pmcLink).pathname.match(/\/articles\/(PMC\d+|pmid\/\d+)\/?/i);
          return match ? `https://pmc.ncbi.nlm.nih.gov/articles/${match[1]}/pdf/` : null;
        })()
        """#
        webView.evaluateJavaScript(script) { value, _ in
            DispatchQueue.main.async {
                guard let value = value as? String, let pdfURL = URL(string: value) else {
                    browserMessage = "Open a PubMed record that has a PMC full-text link, then choose Prepare PDF Downloads again."
                    return
                }
                browserMessage = "PMC may briefly show Preparing to download. Wait for the PDF to appear, then go Back and import the search."
                webView.load(URLRequest(url: pdfURL))
            }
        }
    }
}

private struct SearchWebView: NSViewRepresentable {
    let webView: WKWebView
    let source: ScrapeSource
    let initialURL: URL?
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var nytSignedIn: Bool?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        let target = initialURL ?? source.homeURL
        if webView.url != target {
            webView.load(URLRequest(url: target))
        } else {
            DispatchQueue.main.async {
                currentURL = webView.url
                canGoBack = webView.canGoBack
                canGoForward = webView.canGoForward
            }
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: SearchWebView
        init(parent: SearchWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.currentURL = webView.url
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            guard let url = webView.url,
                  url.host?.lowercased().hasSuffix("nytimes.com") == true else { return }

            // Only an actual authentication page is definitive evidence that
            // the user must sign in. NYT includes dormant login links in the
            // markup of some pages even while an account session is active.
            if url.path.lowercased().contains("/auth/login") {
                parent.nytSignedIn = false
                return
            }
            let script = #"""
            (() => {
              const account = Array.from(document.querySelectorAll('a,button')).some(el =>
                /^(account|my account|profile|account settings)$/i.test((el.innerText || el.textContent || el.getAttribute('aria-label') || '').trim()) ||
                /\/(account|profile)(\/|\?|$)/i.test(el.href || '') ||
                /account|profile/i.test(el.getAttribute('data-testid') || ''));
              return account ? 'signed-in' : 'unknown';
            })()
            """#
            webView.evaluateJavaScript(script) { value, _ in
                DispatchQueue.main.async {
                    if value as? String == "signed-in" { self.parent.nytSignedIn = true }
                    else { self.parent.nytSignedIn = nil }
                }
            }
        }
    }
}
