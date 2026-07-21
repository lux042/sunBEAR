import SwiftUI
import WebKit

struct CIASearchBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentURL: URL?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var webView = WKWebView()
    let onImport: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack)
                Button { webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
                Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Text(currentURL?.absoluteString ?? "CIA Reading Room")
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Import This Search") {
                    guard let currentURL else { return }
                    onImport(currentURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentURL?.path.contains("search") != true)
            }
            .padding(10)
            Divider()
            CIAWebView(webView: webView, currentURL: $currentURL, canGoBack: $canGoBack, canGoForward: $canGoForward)
        }
        .frame(minWidth: 980, minHeight: 700)
    }
}

private struct CIAWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var currentURL: URL?
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        if webView.url == nil, let url = URL(string: "https://www.cia.gov/readingroom/advanced-search-view") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CIAWebView
        init(parent: CIAWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.currentURL = webView.url
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
        }
    }
}
