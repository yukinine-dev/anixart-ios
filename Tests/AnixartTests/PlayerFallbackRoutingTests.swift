import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class PlayerFallbackRoutingTests: XCTestCase {
    private let hostingURL = URL(string: "https://kodikplayer.com/serial/1/hash/720p")!

    @MainActor
    func testWebOverrideWinsOverNativeAndResolvedKodikStreams() {
        for hasKodikStream in [false, true] {
            XCTAssertEqual(resolve(
                supportsDirectPlayback: true,
                hasKodikStream: hasKodikStream,
                prefersWebFallback: true
            ), .web)
        }
    }

    @MainActor
    func testWebOverrideDoesNotReenterKodikGate() {
        XCTAssertEqual(resolve(prefersWebFallback: true), .web)
        XCTAssertEqual(resolve(), .kodik)
    }

    @MainActor
    func testResolvedKodikStreamUsesNativePlayerWithoutOverride() {
        XCTAssertEqual(resolve(hasKodikStream: true), .embedded)
    }

    @MainActor
    func testFailedKodikGateFallsBackToWeb() {
        XCTAssertEqual(resolve(kodikGaveUp: true), .web)
    }

    @MainActor
    func testAbandonedKodikGateStaysWebWhenStreamArrivesLate() {
        XCTAssertEqual(resolve(kodikGaveUp: true), .web)
        XCTAssertEqual(resolve(hasKodikStream: true, kodikGaveUp: true), .web)
    }

    @MainActor
    func testSourcePlayerChoiceStaysWebAfterAdvertFinishes() {
        for hasKodikStream in [false, true] {
            XCTAssertEqual(resolve(
                hasKodikStream: hasKodikStream,
                kodikGaveUp: true,
                prefersWebFallback: true
            ), .web)
            XCTAssertFalse(PlayerScreen.shouldUseWebAdvert(
                kodikGaveUp: true, hasKodikStream: hasKodikStream
            ))
        }
    }

    @MainActor
    func testDirectStreamsKeepRequestedPlayerWithoutOverride() {
        let choices: [(PlayerChoice, PlayerScreen.Route)] = [
            (.embedded, .embedded), (.external, .external), (.web, .web)
        ]
        for (choice, expected) in choices {
            XCTAssertEqual(resolve(choice: choice, supportsDirectPlayback: true), expected)
        }
    }

    @MainActor
    func testMissingAndUnknownHostingUseWebWithoutDirectStreams() {
        for url in [nil, URL(string: "https://example.com/player")] {
            XCTAssertEqual(PlayerScreen.Route.resolve(
                choice: .embedded,
                supportsDirectPlayback: false,
                hostingURL: url,
                hasKodikStream: false,
                kodikGaveUp: false,
                prefersWebFallback: false
            ), .web)
        }
    }

    @MainActor
    func testKodikGateIsOnlyUsedForEmbeddedChoice() {
        for choice in [PlayerChoice.web, .external] {
            XCTAssertEqual(resolve(choice: choice), .web)
        }
    }

    @MainActor
    func testWebAdvertIsNotRepeatedAfterKodikGate() {
        XCTAssertFalse(PlayerScreen.shouldUseWebAdvert(kodikGaveUp: false, hasKodikStream: true))
        XCTAssertFalse(PlayerScreen.shouldUseWebAdvert(kodikGaveUp: true, hasKodikStream: false))
        XCTAssertFalse(PlayerScreen.shouldUseWebAdvert(kodikGaveUp: true, hasKodikStream: true))
        XCTAssertTrue(PlayerScreen.shouldUseWebAdvert(kodikGaveUp: false, hasKodikStream: false))
    }

    @MainActor
    private func resolve(
        choice: PlayerChoice = .embedded,
        supportsDirectPlayback: Bool = false,
        hasKodikStream: Bool = false,
        kodikGaveUp: Bool = false,
        prefersWebFallback: Bool = false
    ) -> PlayerScreen.Route {
        PlayerScreen.Route.resolve(
            choice: choice,
            supportsDirectPlayback: supportsDirectPlayback,
            hostingURL: hostingURL,
            hasKodikStream: hasKodikStream,
            kodikGaveUp: kodikGaveUp,
            prefersWebFallback: prefersWebFallback
        )
    }
}
