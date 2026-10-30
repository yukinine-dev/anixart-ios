import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class KodikRoutingTests: XCTestCase {
    private let hostingURL = URL(string: "https://kodikplayer.com/serial/1/hash/720p?min_age=16")!
    private let advertBase = "https://anixmirai.com/iframe/ad?url="
    private let plainBase = "https://anixmirai.com/iframe?url="

    func testOriginalKodikHostsAreRecognized() {
        for host in ["kodik.cc", "kodik.info", "aniqit.com", "kodikplayer.com", "VIDEO.KODIKPLAYER.COM"] {
            let url = URL(string: "https://\(host)/serial/1/hash/")!
            XCTAssertTrue(KodikWrapper.handles(url), host)
        }
    }

    @MainActor
    func testProductionRouteSelectsKodikForOriginalHostingURL() throws {
        let screen = try player(target: PlaybackTarget(pageURL: hostingURL))
        let route = screen.resolvedChoice

        XCTAssertEqual(route, .kodik)
    }

    @MainActor
    func testAdvertWrapperDoesNotReplaceHostingURLForProductionRouting() throws {
        let screen = try player(target: PlaybackTarget(pageURL: hostingURL))
        let original = try XCTUnwrap(screen.target.pageURL)
        let wrapped = try XCTUnwrap(KodikWrapper.url(for: original, base: advertBase))
        let components = try XCTUnwrap(URLComponents(url: wrapped, resolvingAgainstBaseURL: false))
        let route = screen.resolvedChoice

        XCTAssertEqual(components.host, "anixmirai.com")
        XCTAssertEqual(components.path, "/iframe/ad")
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "url" }?.value,
            "https://kodikplayer.com/serial/1/hash/720p"
        )
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "v" }?.value,
            "\(AnixartEnvironment.versionCode)"
        )
        XCTAssertFalse(KodikWrapper.handles(wrapped))
        XCTAssertEqual(screen.target.pageURL, hostingURL)
        XCTAssertEqual(route, .kodik)
    }

    @MainActor
    func testWrappedURLAloneUsesWebFallback() throws {
        let wrapped = try XCTUnwrap(KodikWrapper.url(for: hostingURL, base: advertBase))
        let screen = try player(target: PlaybackTarget(pageURL: wrapped))
        let route = screen.resolvedChoice

        XCTAssertFalse(KodikWrapper.handles(wrapped))
        XCTAssertEqual(route, .web)
    }

    @MainActor
    func testUnknownHostingUsesWebFallback() throws {
        for host in ["example.com", "kodikplayer.com.example.com"] {
            let url = URL(string: "https://\(host)/video/1")!
            let screen = try player(target: PlaybackTarget(pageURL: url))
            let route = screen.resolvedChoice

            XCTAssertFalse(KodikWrapper.handles(url), host)
            XCTAssertEqual(route, .web, host)
        }
    }

    @MainActor
    func testRequestedWebAndExternalPlayersDoNotEnterKodikGate() throws {
        for choice in [PlayerChoice.web, .external] {
            let screen = try player(target: PlaybackTarget(pageURL: hostingURL), choice: choice)
            let route = screen.resolvedChoice

            XCTAssertEqual(route, .web, choice.rawValue)
        }
    }

    @MainActor
    func testDirectPlaybackKeepsRequestedPlayer() throws {
        let stream = StreamVariant(url: URL(string: "https://example.com/episode.m3u8")!)
        let target = PlaybackTarget(variants: [stream], pageURL: hostingURL)
        let choices: [(PlayerChoice, PlayerScreen.Route)] = [
            (.embedded, .embedded), (.external, .external), (.web, .web)
        ]

        for (choice, expected) in choices {
            let screen = try player(target: target, choice: choice)
            let route = screen.resolvedChoice

            XCTAssertEqual(route, expected, choice.rawValue)
        }
    }

    func testPlainWrapperRemainsAvailableForWebFallback() throws {
        let wrapped = try XCTUnwrap(KodikWrapper.url(for: hostingURL, base: plainBase))
        let components = try XCTUnwrap(URLComponents(url: wrapped, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "anixmirai.com")
        XCTAssertEqual(components.path, "/iframe")
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "url" }?.value,
            "https://kodikplayer.com/serial/1/hash/720p"
        )
        XCTAssertEqual(
            components.queryItems?.first { $0.name == "v" }?.value,
            "\(AnixartEnvironment.versionCode)"
        )
    }

    func testMissingWrapperConfigurationStillReturnsNil() {
        XCTAssertNil(KodikWrapper.url(for: hostingURL, base: nil))
        XCTAssertNil(KodikWrapper.url(for: hostingURL, base: ""))
    }

    @MainActor
    private func player(target: PlaybackTarget, choice: PlayerChoice = .embedded) throws -> PlayerScreen {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KodikRoutingTests.\(UUID().uuidString)"))
        let episode = try JSONDecoder().decode(Episode.self, from: Data("{}".utf8))

        return PlayerScreen(
            episode: episode,
            releaseTitle: "Test release",
            preferences: PlaybackPreferences(defaults: defaults),
            onProgress: { _ in },
            onFinished: {},
            choice: choice,
            target: target
        )
    }
}
