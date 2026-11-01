import Foundation
import XCTest
import Lottie
import AnixartKit
@testable import Anixart

/// Self-contained JSON and injected transports. No artwork or account is fetched.
final class ProfileBadgeAnimationTests: XCTestCase {
    private var fixture: Data {
        Data(#"{"v":"5.7.4","fr":30,"ip":0,"op":60,"w":64,"h":64,"layers":[]}"#.utf8)
    }

    func testNativeLottieDecodePreservesAuthoredTiming() throws {
        let animation = try XCTUnwrap(ProfileBadgeAnimationLoader.decode(fixture))
        XCTAssertEqual(animation.framerate, 30)
        XCTAssertEqual(animation.duration, 2, accuracy: 0.001)
        XCTAssertEqual(animation.size.width, 64)
        XCTAssertEqual(animation.size.height, 64)
    }

    func testMalformedBitmapOversizedAndInvalidGeometryAreNotAnimations() throws {
        for data in [Data(), Data("{}".utf8), Data("<html>error</html>".utf8), Data("GIF89a".utf8),
                     Data(count: ProfileBadgeAnimationLoader.encodedByteLimit + 1)] {
            XCTAssertNil(ProfileBadgeAnimationLoader.decode(data))
        }
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        for (key, value) in [("fr", 0), ("w", 0), ("h", 5000), ("op", 0), ("op", 20000)] {
            var json = source
            json[key] = value
            XCTAssertNil(ProfileBadgeAnimationLoader.decode(try JSONSerialization.data(withJSONObject: json)), key)
        }
    }

    func testLoaderReusesTheSameParsedModelForTheSameURL() async throws {
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let url = URL(string: "https://animation-tests.invalid/badge.json")!
        let first = await loader.animation(for: url)
        let second = await loader.animation(for: url)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === second)
        let requests = await transport.requests
        let count = await loader.cachedAnimationCount
        XCTAssertEqual(requests, [url])
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testConcurrentRequestsShareOneDownloadAndDecode() async throws {
        let gate = ProfileTestGate()
        defer { gate.release() }
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture, gate: gate)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let url = URL(string: "https://animation-tests.invalid/shared.json")!
        let first = Task { await loader.animation(for: url) }
        defer { first.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        let second = Task { await loader.animation(for: url) }
        defer { second.cancel() }
        gate.release()
        let a = await first.value
        let b = await second.value
        let requests = await transport.requests
        XCTAssertNotNil(a)
        XCTAssertTrue(a === b)
        XCTAssertEqual(requests, [url])
    }

    func testInvalidPrimaryResponseFallsBackToMirror() async throws {
        let url = URL(string: "https://static.badges.invalid/badge.json")!
        let mirror = AnixartURL.mirrored(url)
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture,
                                                           responses: [url: Data("<html>unavailable</html>".utf8)])
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let animation = await loader.animation(for: url)
        let requests = await transport.requests
        XCTAssertNotNil(animation)
        XCTAssertEqual(requests, [url, mirror])
    }

    func testFailedLoadIsNotCachedAsASuccess() async {
        let transport = ProfileBadgeAnimationTestTransport(fallback: Data("{}".utf8))
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let url = URL(string: "https://animation-tests.invalid/invalid.json")!
        let animation = await loader.animation(for: url)
        let count = await loader.cachedAnimationCount
        let bytes = await loader.cachedByteCount
        XCTAssertNil(animation)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(bytes, 0)
    }

    func testLocalAndNonHTTPURLsNeverReachTheTransport() async {
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        for value in ["file:///private/badge.json", "javascript:alert(1)", "badge.json"] {
            let animation = await loader.animation(for: URL(string: value)!)
            XCTAssertNil(animation)
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCountBoundUsesLRUAndKeepsRecentlyAccessedAnimation() async {
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let urls = (0...ProfileBadgeAnimationLoader.cacheCountLimit).map {
            URL(string: "https://animation-tests.invalid/\($0).json")!
        }
        for url in urls.dropLast() {
            let animation = await loader.animation(for: url)
            XCTAssertNotNil(animation)
        }
        _ = await loader.animation(for: urls[0])
        _ = await loader.animation(for: urls.last!)
        _ = await loader.animation(for: urls[0])
        _ = await loader.animation(for: urls[1])
        let requests = await transport.requests
        let count = await loader.cachedAnimationCount
        XCTAssertEqual(requests.filter { $0 == urls[0] }.count, 1)
        XCTAssertEqual(requests.filter { $0 == urls[1] }.count, 2)
        XCTAssertEqual(count, ProfileBadgeAnimationLoader.cacheCountLimit)
    }

    func testEncodedByteBudgetAlsoBoundsTheCache() async {
        let data = fixture + Data(repeating: 0x20, count: ProfileBadgeAnimationLoader.encodedByteLimit - fixture.count)
        let transport = ProfileBadgeAnimationTestTransport(fallback: data)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let capacity = ProfileBadgeAnimationLoader.cacheByteLimit / data.count
        for index in 0...capacity {
            let animation = await loader.animation(for: URL(string: "https://animation-tests.invalid/large-\(index).json")!)
            XCTAssertNotNil(animation)
        }
        let count = await loader.cachedAnimationCount
        let bytes = await loader.cachedByteCount
        XCTAssertEqual(count, capacity)
        XCTAssertLessThanOrEqual(bytes, ProfileBadgeAnimationLoader.cacheByteLimit)
    }

    @MainActor
    func testCancelledSubscriberCannotPublishButSharedModelRemainsReusable() async {
        let gate = ProfileTestGate()
        defer { gate.release() }
        let transport = ProfileBadgeAnimationTestTransport(fallback: fixture, gate: gate)
        let loader = ProfileBadgeAnimationLoader(fetchData: { await transport.data(for: $0) })
        let url = URL(string: "https://animation-tests.invalid/cancelled.json")!
        let first = Task { await loader.animation(for: url) }
        defer { first.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        first.cancel()
        gate.release()
        let cancelled = await first.value
        let reused = await loader.animation(for: url)
        let requests = await transport.requests
        XCTAssertNil(cancelled)
        XCTAssertNotNil(reused)
        XCTAssertEqual(requests, [url])
    }

    @MainActor
    func testVisibilitySceneReduceMotionAndResourceSavingAllGatePlayback() {
        XCTAssertTrue(ProfileBadgePlayback.allowsAnimation(isVisible: true, isActive: true,
                                                           reduceMotion: false, resourceSaving: false))
        XCTAssertFalse(ProfileBadgePlayback.allowsAnimation(isVisible: false, isActive: true,
                                                            reduceMotion: false, resourceSaving: false))
        XCTAssertFalse(ProfileBadgePlayback.allowsAnimation(isVisible: true, isActive: false,
                                                            reduceMotion: false, resourceSaving: false))
        XCTAssertFalse(ProfileBadgePlayback.allowsAnimation(isVisible: true, isActive: true,
                                                            reduceMotion: true, resourceSaving: false))
        XCTAssertFalse(ProfileBadgePlayback.allowsAnimation(isVisible: true, isActive: true,
                                                            reduceMotion: false, resourceSaving: true))
    }

    @MainActor
    func testPausingKeepsTheSameAnimationAndItsCurrentFrame() throws {
        let animation = try XCTUnwrap(ProfileBadgeAnimationLoader.decode(fixture))
        let view = LottieAnimationView(animation: animation)
        view.currentProgress = 0.4
        ProfileBadgePlayback.update(view, animation: animation, isAnimating: false)
        XCTAssertTrue(view.animation === animation)
        XCTAssertEqual(view.currentProgress, 0.4, accuracy: 0.001)
        XCTAssertFalse(view.isAnimationPlaying)
        XCTAssertFalse(view.isAnimationQueued)
    }

    @MainActor
    func testReplacingArtworkStartsPausedAtTheFirstFrame() throws {
        let first = try XCTUnwrap(ProfileBadgeAnimationLoader.decode(fixture))
        let replacement = try XCTUnwrap(ProfileBadgeAnimationLoader.decode(fixture))
        let view = LottieAnimationView(animation: first)
        view.currentProgress = 0.7
        ProfileBadgePlayback.update(view, animation: replacement, isAnimating: false)
        XCTAssertTrue(view.animation === replacement)
        XCTAssertEqual(view.currentProgress, 0, accuracy: 0.001)
        ProfileBadgeLottieView.dismantleUIView(view, coordinator: ())
        XCTAssertNil(view.animation)
        XCTAssertFalse(view.isAnimationPlaying)
    }
}

private actor ProfileBadgeAnimationTestTransport {
    private let fallback: Data?
    private let responses: [URL: Data]
    private let gate: ProfileTestGate?
    private(set) var requests: [URL] = []

    init(fallback: Data?, responses: [URL: Data] = [:], gate: ProfileTestGate? = nil) {
        self.fallback = fallback
        self.responses = responses
        self.gate = gate
    }

    func data(for url: URL) async -> Data? {
        requests.append(url)
        if let gate { await gate.wait() }
        return responses[url] ?? fallback
    }
}
