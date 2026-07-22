import SwiftUI
import WebKit

struct SearchBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView = WKWebView()
    @State private var browserMessage = ""
    let source: ScrapeSource
    let initialURL: URL?
    let onImport: (URL) -> Void

    init(source: ScrapeSource, initialURL: URL? = nil, onImport: @escaping (URL) -> Void) {
        self.source = source
        self.initialURL = initialURL
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
                Button("Cancel") { dismiss() }
                Button("Import This \(source.title) Search") {
                    guard let currentURL else { return }
                    onImport(currentURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!source.canImport(currentURL))
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
            Divider()
            SearchWebView(webView: webView, source: source, initialURL: initialURL, currentURL: $currentURL, canGoBack: $canGoBack, canGoForward: $canGoForward)
        }
        .frame(minWidth: 980, minHeight: 700)
    }

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

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        if webView.url == nil {
            webView.load(URLRequest(url: initialURL ?? source.homeURL))
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
        }
    }
}
