import SwiftUI
import WebKit
import os
import AnixartKit

/// Kodik's own player page, shown so that its advert plays as Kodik intends.
///
/// This is the Android app's flow, not a way around it. `KodikAdActivity` loads
/// the page in a WebView, dispatches one tap in the centre on page load because
/// autoplay needs a gesture, and registers a JavaScript bridge named
/// `KodikInterface` -- which Kodik's own player then calls back as
/// `advertEnded()`. Kodik wrote that callback. Only afterwards does the episode
/// open in the player the user chose.
///
/// The stream is not in the page's HTML. Measured in CI: no `.mp4` and no
/// `.m3u8` anywhere in it, two scripts, one of them `app.player_single.js`,
/// which fetches the links at runtime (the APK's error handler watches for a
/// 500 on `/ftor`, which is that request). So rather than reimplementing
/// somebody's private request, this lets the page do its own work and then asks
/// it what it ended up playing.
@MainActor
struct KodikAdView: UIViewRepresentable {
    let url: URL
    /// Called with every media URL the page turned out to load, once its advert
    /// reports finished -- or once the wait runs out, since a page that never
    /// calls back should not strand the user.
    let onResolved: ([URL]) -> Void
    /// Called when the page itself could not be loaded at all.
    let onFailure: (String) -> Void

    func makeCoordinator() -> Bridge {
        Bridge(onResolved: onResolved, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Bridge.channel)

        // Kodik's player calls `KodikInterface.advertEnded()`. On Android that
        // name comes from addJavascriptInterface; here it has to be shimmed onto
        // the message handler, under the same name the page expects.
        controller.addUserScript(WKUserScript(
            source: """
            window.KodikInterface = window.KodikInterface || {};
            window.KodikInterface.advertEnded = function () {
                window.webkit.messageHandlers.\(Bridge.channel).postMessage({ event: "advertEnded" });
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        // The advert has to be able to start on its own; Android gets there with
        // a synthetic tap instead.
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        context.coordinator.adopt(view)

        // The same identity the web player presents, since this is the same page
        // being asked to behave the same way.
        view.customUserAgent = EmbedPlayerView.userAgent

        var request = URLRequest(url: url)
        request.setValue(AnixartEnvironment.webBaseURL.absoluteString, forHTTPHeaderField: "Referer")
        view.load(request)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Bridge) {
        coordinator.stop()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: Bridge.channel)
    }

    /// Carries the advert's callback back from the page, and reads off what it
    /// played.
    @MainActor
    final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let channel = "anixartKodik"
        private static let log = Logger(subsystem: "app.anixart.client", category: "kodik")

        /// Long enough for an advert, short enough not to look broken. A page
        /// that never calls back still has to let the user through.
        private static let patience: Duration = .seconds(45)

        private let onResolved: ([URL]) -> Void
        private let onFailure: (String) -> Void
        private weak var view: WKWebView?
        private var timeout: Task<Void, Never>?
        private var hasFinished = false

        init(onResolved: @escaping ([URL]) -> Void, onFailure: @escaping (String) -> Void) {
            self.onResolved = onResolved
            self.onFailure = onFailure
            super.init()
        }

        func adopt(_ view: WKWebView) {
            self.view = view
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.patience)
                guard let self, !self.hasFinished else { return }
                Self.log.notice("advert did not report finished; reading the page anyway")
                await self.finish()
            }
        }

        func stop() {
            timeout?.cancel()
            timeout = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The Android client taps the centre once here, because an advert
            // will not start without a gesture. This is the same nudge.
            webView.evaluateJavaScript("""
            (function () {
                var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight / 2);
                if (el && el.click) { el.click(); }
                return true;
            })();
            """)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            report(failure: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            report(failure: error.localizedDescription)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  body["event"] as? String == "advertEnded"
            else { return }
            Self.log.notice("advert finished")
            Task { await finish() }
        }

        /// Asks the page what it is playing.
        ///
        /// `video.currentSrc` is the direct answer, but a player using Media
        /// Source gets a `blob:` URL there, which is no use outside the page --
        /// so the resource timings are read too. They name every URL the page
        /// fetched, which is where an `.m3u8` or `.mp4` shows up without
        /// touching the player's internals.
        private func finish() async {
            guard !hasFinished, let view else { return }
            hasFinished = true
            stop()

            let script = """
            (function () {
                var video = document.querySelector("video");
                var current = video ? (video.currentSrc || video.src || "") : "";
                var loaded = [];
                try {
                    loaded = performance.getEntriesByType("resource")
                        .map(function (entry) { return entry.name; })
                        .filter(function (name) { return /\\.m3u8|\\.mp4|\\.ts(\\?|$)/.test(name); });
                } catch (error) { loaded = []; }
                return JSON.stringify({ current: current, loaded: loaded });
            })();
            """

            let raw = try? await view.evaluateJavaScript(script) as? String
            guard let raw,
                  let data = raw.data(using: .utf8),
                  let answer = try? JSONDecoder().decode(PageAnswer.self, from: data)
            else {
                report(failure: "страница не ответила, что воспроизводит")
                return
            }

            var candidates: [URL] = []
            if !answer.current.isEmpty, !answer.current.hasPrefix("blob:"),
               let url = URL(string: answer.current) {
                candidates.append(url)
            }
            candidates += answer.loaded.compactMap(URL.init(string:))

            Self.log.notice("""
            page played current=\(answer.current, privacy: .public) \
            loaded=\(answer.loaded.count, privacy: .public)
            """)
            for name in answer.loaded.prefix(6) {
                Self.log.notice("page loaded \(name, privacy: .public)")
            }

            onResolved(candidates)
        }

        private func report(failure: String) {
            guard !hasFinished else { return }
            hasFinished = true
            stop()
            Self.log.error("kodik page failed: \(failure, privacy: .public)")
            onFailure(failure)
        }

        private struct PageAnswer: Decodable {
            var current: String
            var loaded: [String]
        }
    }
}
