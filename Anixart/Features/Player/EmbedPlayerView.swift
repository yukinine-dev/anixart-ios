import SwiftUI
import WebKit
import AnixartKit

/// Hosts a hosting's own player page (Kodik, Sibnet, VK Video).
///
/// Three things these pages need, and that a default `WKWebView` does not give them:
///
///   - inline playback, otherwise iOS hijacks the video into its own full-screen
///     player and the page's controls stop working;
///   - a desktop-ish user agent, since several hostings serve a stripped page or a
///     "open in app" interstitial to mobile Safari;
///   - a `Referer`, which the hostings check before handing out the stream. The
///     Android app sends `https://anixart-app.com` for the same reason.
///
/// This is also the part of the port most likely to need maintenance: these pages
/// change their player and their anti-embedding checks without notice.
@MainActor
struct EmbedPlayerView: UIViewRepresentable {
    let url: URL
    let title: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url && !webView.isLoading {
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private var request: URLRequest {
        var request = URLRequest(url: url)
        request.setValue(AnixartEnvironment.webBaseURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Keeps the player page from navigating away to a store listing or an ad
        /// landing page, which several hostings try on first tap.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = target.scheme?.lowercased()
            let isWeb = scheme == "http" || scheme == "https" || scheme == "about"
            if navigationAction.navigationType == .linkActivated || !isWeb {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
