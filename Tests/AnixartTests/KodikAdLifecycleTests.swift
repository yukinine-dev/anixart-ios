import Foundation
import WebKit
import XCTest
@testable import Anixart

final class KodikAdLifecycleTests: XCTestCase {
    private let advertURL = URL(string: "https://example.com/advert.mp4")!
    private let episodeURL = URL(string: "https://example.com/episode.m3u8")!

    @MainActor
    func testDismantleCancelsTimeoutWithoutResolvingAdvertAsEpisode() async {
        let callback = expectation(description: "A removed advert page must not call back")
        callback.isInverted = true
        let bridge = KodikAdView.Bridge(
            onResolved: { _, _ in callback.fulfill() },
            onFailure: { _ in callback.fulfill() }
        )
        let view = WKWebView()
        defer { bridge.stop() }
        bridge.adopt(view)
        request(advertURL, from: bridge)

        KodikAdView.dismantleUIView(view, coordinator: bridge)

        await fulfillment(of: [callback], timeout: 0.2)
    }

    @MainActor
    func testResolutionQueuedBeforeStopIsIgnored() async {
        let callback = expectation(description: "A queued resolution must not outlive its page")
        callback.isInverted = true
        let bridge = KodikAdView.Bridge(
            onResolved: { _, _ in callback.fulfill() },
            onFailure: { _ in callback.fulfill() }
        )
        defer { bridge.stop() }
        bridge.receive(["event": "advertEnded"])
        request(episodeURL, from: bridge)

        // The media report queued finish() on the main actor, but the user
        // leaves before that task gets a chance to run.
        bridge.stop()

        await fulfillment(of: [callback], timeout: 0.2)
    }

    @MainActor
    func testLateMessagesAndNavigationFailuresAfterStopAreIgnored() async {
        let callback = expectation(description: "Late events must not revive a stopped bridge")
        callback.isInverted = true
        let bridge = KodikAdView.Bridge(
            onResolved: { _, _ in callback.fulfill() },
            onFailure: { _ in callback.fulfill() }
        )
        defer { bridge.stop() }
        bridge.stop()
        bridge.stop()

        let view = WKWebView()
        bridge.adopt(view)
        bridge.receive(["event": "hello", "url": "https://example.com/player"])
        bridge.receive(["event": "advertEnded"])
        request(episodeURL, from: bridge)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        bridge.webView(view, didFail: nil, withError: error)
        bridge.webView(view, didFailProvisionalNavigation: nil, withError: error)

        XCTAssertTrue(bridge.frames.isEmpty)
        await fulfillment(of: [callback], timeout: 0.2)
    }

    @MainActor
    func testAdvertCompletionStillResolvesEpisodeExactlyOnce() async {
        let resolved = expectation(description: "The active advert gate resolves the episode")
        resolved.assertForOverFulfill = true
        var resolutionCount = 0
        var resolvedMedia: [KodikAdView.Media] = []
        var diagnosis: KodikAdView.Diagnosis?
        let bridge = KodikAdView.Bridge(
            onResolved: { media, result in
                resolutionCount += 1
                resolvedMedia = media
                diagnosis = result
                resolved.fulfill()
            },
            onFailure: { reason in XCTFail("Unexpected failure: \(reason)") }
        )
        defer { bridge.stop() }
        request(advertURL, from: bridge)
        bridge.receive(["event": "advertEnded"])
        request(episodeURL, from: bridge)
        request(episodeURL, from: bridge)

        await fulfillment(of: [resolved], timeout: 1)

        XCTAssertEqual(resolutionCount, 1)
        XCTAssertEqual(diagnosis?.advertFinished, true)
        XCTAssertEqual(resolvedMedia.first, KodikAdView.Media(url: advertURL, afterAdvert: false))
        XCTAssertEqual(resolvedMedia.last, KodikAdView.Media(url: episodeURL, afterAdvert: true))
        XCTAssertEqual(KodikAdView.episodeStream(from: resolvedMedia), episodeURL)

        bridge.receive(["event": "advertEnded"])
        request(episodeURL, from: bridge)
        bridge.webView(WKWebView(), didFail: nil, withError: NSError(domain: NSURLErrorDomain, code: -1))
        await Task.yield()
        XCTAssertEqual(resolutionCount, 1)
    }

    @MainActor
    private func request(_ url: URL, from bridge: KodikAdView.Bridge) {
        bridge.receive(["event": "request", "kind": "video", "url": url.absoluteString])
    }
}
