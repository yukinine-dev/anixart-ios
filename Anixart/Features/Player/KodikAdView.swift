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
    /// calls back should not strand the user. The second argument is what the
    /// page was seen doing, so a screen can show why nothing was found.
    let onResolved: ([URL], Diagnosis) -> Void

    /// What the page was observed doing, for when it yields nothing.
    struct Diagnosis: Equatable {
        var frames: [String] = []
        var requests: [String] = []
        var advertFinished = false
    }
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
            source: Self.reporter(channel: Bridge.channel),
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

    /// Runs in every frame, not just the main one.
    ///
    /// The first attempt read `document.querySelector("video")` and the resource
    /// timings from the main frame after the fact, and got nothing at all --
    /// not even a timing -- which is what a player living in a child frame looks
    /// like. A frame can only see its own document and its own timings, so the
    /// reporting has to happen inside each of them, as it happens.
    ///
    /// It watches rather than drives: the URLs the frame asks for, and whatever
    /// a `<video>` ends up playing. Nothing here reimplements the player's own
    /// request -- it is the same information the browser would show in its
    /// network panel.
    private static func reporter(channel: String) -> String {
        """
        (function () {
            var post = function (payload) {
                try {
                    window.webkit.messageHandlers.\(channel).postMessage(payload);
                } catch (error) { /* a frame without the handler is fine */ }
            };

            // Says the script runs in this frame at all. Without it, a report of
            // zero requests could equally mean the page did nothing or that this
            // never executed -- which is exactly the ambiguity the first three
            // measurements left.
            post({ event: "hello", url: String(location.href) });

            // Kodik's player calls this when its advert is over; on Android the
            // name comes from addJavascriptInterface.
            window.KodikInterface = window.KodikInterface || {};
            window.KodikInterface.advertEnded = function () {
                post({ event: "advertEnded" });
            };

            var seen = {};
            var note = function (kind, url) {
                if (!url || seen[url]) { return; }
                seen[url] = true;
                post({ event: "request", kind: kind, url: String(url) });
            };

            // Every URL the frame asks for. Reported in full while the count is
            // small, because which request comes first is the diagnostic: no
            // `/ftor` at all means the page stalled before resolving anything.
            var fetch0 = window.fetch;
            if (fetch0) {
                window.fetch = function (input) {
                    note("fetch", typeof input === "string" ? input : (input && input.url));
                    return fetch0.apply(this, arguments);
                };
            }
            var open0 = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function (method, url) {
                note("xhr", url);
                return open0.apply(this, arguments);
            };

            // Catches what the hooks cannot: a native `<video src>`, a worker,
            // anything loaded by an API this script did not wrap. Telemetry and
            // adverts are skipped so the interesting rows are not buried.
            var boring = /mc[.]yandex[.]ru|adsbygoogle|googlesyndication|doubleclick|[.]css|[.]woff|[.]png|[.]jpg|[.]svg|[.]gif/;
            try {
                new PerformanceObserver(function (list) {
                    var entries = list.getEntries();
                    for (var i = 0; i < entries.length; i++) {
                        var name = entries[i].name;
                        if (!boring.test(name)) { note("load", name); }
                    }
                }).observe({ type: "resource", buffered: true });
            } catch (error) { /* older WebKit */ }

            var look = function () {
                var videos = document.querySelectorAll("video");
                for (var i = 0; i < videos.length; i++) {
                    note("video", videos[i].currentSrc || videos[i].src);
                }
            };
            new MutationObserver(look).observe(document.documentElement || document, {
                childList: true, subtree: true, attributes: true, attributeFilter: ["src"]
            });
            document.addEventListener("loadedmetadata", look, true);
            setInterval(look, 2000);

            // An advert will not start without a gesture, and the Android client
            // dispatches one tap in the centre. Each frame nudges its own.
            var nudge = function () {
                try {
                    var el = document.elementFromPoint(
                        Math.floor(window.innerWidth / 2),
                        Math.floor(window.innerHeight / 2)
                    );
                    if (el && el.click) { el.click(); }
                } catch (error) { /* nothing to click yet */ }
            };
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", nudge);
            } else {
                nudge();
            }
            setTimeout(nudge, 1500);
        })();
        """
    }

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
        private static let patience: Duration = .seconds(90)

        private let onResolved: ([URL], Diagnosis) -> Void
        private let onFailure: (String) -> Void
        private weak var view: WKWebView?
        private var timeout: Task<Void, Never>?
        private var hasFinished = false
        private var advertFinished = false
        /// Media URLs the frames reported, in the order they asked for them.
        private var media: [URL] = []
        /// Every request, for the diagnostic: whether the page got as far as
        /// resolving its links at all.
        private var requests: [String] = []
        /// Frames whose copy of the script checked in.
        private(set) var frames: [String] = []

        init(onResolved: @escaping ([URL], Diagnosis) -> Void, onFailure: @escaping (String) -> Void) {
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
                  let event = body["event"] as? String
            else { return }

            switch event {
            case "hello":
                let where_ = body["url"] as? String ?? "?"
                if frames.count < 12 {
                    frames.append(where_)
                    Self.log.notice("frame alive \(where_, privacy: .public)")
                }
            case "advertEnded":
                advertFinished = true
                Self.log.notice("advert finished")
                Task { await finish() }
            case "request":
                let raw = body["url"] as? String ?? ""
                let kind = body["kind"] as? String ?? "?"
                if requests.count < 160 {
                    requests.append("\(kind) \(raw)")
                }
                if Self.isInteresting(raw) {
                    // Logged as it happens, because this is the row that matters
                    // and it arrives after a crowd of telemetry.
                    Self.log.notice("page asked \(kind, privacy: .public) \(raw, privacy: .public)")
                }
                if Self.isMedia(raw), !raw.hasPrefix("blob:"), let url = URL(string: raw) {
                    media.append(url)
                }
            default:
                break
            }
        }

        /// Asks the page what it is playing.
        ///
        /// `video.currentSrc` is the direct answer, but a player using Media
        /// Source gets a `blob:` URL there, which is no use outside the page --
        /// so the resource timings are read too. They name every URL the page
        /// fetched, which is where an `.m3u8` or `.mp4` shows up without
        /// touching the player's internals.
        private func finish() async {
            guard !hasFinished else { return }
            hasFinished = true
            stop()

            Self.log.notice("\(self.frames.count, privacy: .public) frames alive, \(self.requests.count, privacy: .public) urls asked, \(self.media.count, privacy: .public) media")
            if media.isEmpty, !requests.isEmpty {
                // Which requests did happen says where it stopped: no `/ftor`
                // means the links were never resolved.
                for line in requests.prefix(12) {
                    Self.log.notice("page request \(line, privacy: .public)")
                }
            }

            // The frames report as they go, so this only fills in a player that
            // set a plain `src` before the script was injected.
            if media.isEmpty, let view {
                let script = """
                (function () {
                    var video = document.querySelector("video");
                    return video ? (video.currentSrc || video.src || "") : "";
                })();
                """
                if let current = try? await view.evaluateJavaScript(script) as? String,
                   !current.isEmpty,
                   !current.hasPrefix("blob:"),
                   let url = URL(string: current) {
                    media.append(url)
                }
            }

            onResolved(media, Diagnosis(
                frames: frames,
                requests: requests,
                advertFinished: advertFinished
            ))
        }

        private func report(failure: String) {
            guard !hasFinished else { return }
            hasFinished = true
            stop()
            Self.log.error("kodik page failed: \(failure, privacy: .public)")
            onFailure(failure)
        }

        /// Worth a log line of its own: the stream, or the CDN that serves it.
        private static func isInteresting(_ url: String) -> Bool {
            if isMedia(url) { return true }
            let lowered = url.lowercased()
            for marker in ["solodcdn", "kodik", "/ftor", "cloud.", "manifest", "/get_", "video"]
            where lowered.contains(marker) {
                return true
            }
            return false
        }

        private static func isMedia(_ url: String) -> Bool {
            let lowered = url.lowercased()
            for marker in [".m3u8", ".mp4", ".mpd"] where lowered.contains(marker) {
                return true
            }
            return false
        }
    }
}
