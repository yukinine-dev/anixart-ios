import Foundation
import SwiftUI
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileThemeLayoutTests: XCTestCase {
    private func layout(_ fields: String = "") throws -> ProfileThemeLayout {
        ProfileThemeLayout(theme: try profileTestDecode(ProfileTheme.self, "{\"id\":7\(fields)}"))
    }

    func testImageKeysIncludeURLAndBoundedRoundedDecodeSize() throws {
        let url = try XCTUnwrap(URL(string: "https://theme-tests.invalid/icon#1200"))
        let first = ImageRequestKey(url: url, pixelSize: 256.1)
        XCTAssertEqual(first.pixelSize, 257)
        XCTAssertEqual(first, ImageRequestKey(url: url, pixelSize: 256.9))
        XCTAssertNotEqual(first, ImageRequestKey(url: url, pixelSize: 257.1))
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: 0).pixelSize, 1)
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: -10).pixelSize, 1)
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: .nan).pixelSize, 1200)
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: .infinity, limit: 1000).pixelSize, 1000)
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: 50_000, limit: 2048).pixelSize, 2048)
        XCTAssertEqual(ImageRequestKey(url: url, pixelSize: 4096).pixelSize, 4096)

        let otherURL = try XCTUnwrap(URL(string: "https://theme-tests.invalid/icon#1200:257"))
        XCTAssertNotEqual(first.cacheKey, ImageRequestKey(url: otherURL, pixelSize: 257).cacheKey)
        XCTAssertEqual(first.cacheKey as String, "\(url.absoluteString.utf8.count):\(url.absoluteString):257")
    }

    func testAndroidColorsUseAlphaFirstAndRejectUnknownFormats() throws {
        let color = try XCTUnwrap(ProfileThemeColor.components(" #80402010 "))
        XCTAssertEqual(color.alpha, 128.0 / 255)
        XCTAssertEqual(color.red, 64.0 / 255)
        XCTAssertEqual(color.green, 32.0 / 255)
        XCTAssertEqual(color.blue, 16.0 / 255)
        XCTAssertEqual(ProfileThemeColor.components("#112233")?.alpha, 1)
        XCTAssertEqual(ProfileThemeColor.components("#00000000")?.alpha, 0)
        XCTAssertEqual(ProfileThemeColor.components("DarkGrey"), ProfileThemeColor.components("#444444"))
        XCTAssertEqual(ProfileThemeColor.components("lime"), ProfileThemeColor.components("#00FF00"))
        for text in ["#123", "#12345", "#1234567", "#123456789", "#GG0000", "unknown", ""] {
            XCTAssertNil(ProfileThemeColor.components(text), text)
        }
        XCTAssertNil(ProfileThemeColor.components(nil))
        XCTAssertEqual(ProfileThemeLayout.alpha(-1, fallback: 0.5), 0)
        XCTAssertEqual(ProfileThemeLayout.alpha(2, fallback: 0.5), 1)
        XCTAssertEqual(ProfileThemeLayout.alpha(.nan, fallback: 0.5), 0.5)
        XCTAssertEqual(ProfileThemeLayout.alpha(nil, fallback: 0.5), 0.5)
    }

    func testGradientDirectionsAndAndroidRadialRadius() {
        let expected: [(ProfileThemeLayout.GradientDirection, UnitPoint, UnitPoint)] = [
            (.leftToRight, UnitPoint(x: 0, y: 0), UnitPoint(x: 1, y: 0)),
            (.topToBottom, UnitPoint(x: 0, y: 0), UnitPoint(x: 0, y: 1)),
            (.bottomToTop, UnitPoint(x: 0, y: 1), UnitPoint(x: 0, y: 0)),
            (.diagonalTLBR, .topLeading, .bottomTrailing),
            (.diagonalTRBL, .topTrailing, .bottomLeading),
            (.radial, .center, .center)
        ]
        for (direction, start, end) in expected {
            XCTAssertEqual(ProfileThemeLayout.GradientDirection(direction.rawValue.uppercased()), direction)
            XCTAssertEqual(direction.endpoints.start, start)
            XCTAssertEqual(direction.endpoints.end, end)
        }
        XCTAssertEqual(ProfileThemeLayout.GradientDirection(nil), .topToBottom)
        XCTAssertEqual(ProfileThemeLayout.GradientDirection("future_direction"), .topToBottom)
        XCTAssertEqual(ProfileThemeLayout.radialRadius(for: CGSize(width: 300, height: 400)), 200, accuracy: 0.001)
    }

    func testBackgroundCropStretchAndNativeTileScale() {
        let image = CGSize(width: 200, height: 100)
        let container = CGSize(width: 100, height: 100)
        XCTAssertEqual(ProfileThemeLayout.backgroundRect(imageSize: image, container: container, mode: .centerCrop),
                       CGRect(x: -50, y: 0, width: 200, height: 100))
        XCTAssertEqual(ProfileThemeLayout.backgroundRect(imageSize: image, container: container, mode: .fitXY),
                       CGRect(origin: .zero, size: container))
        XCTAssertEqual(ProfileThemeLayout.backgroundRect(imageSize: .zero, container: container, mode: .centerCrop), .zero)
        XCTAssertEqual(ProfileThemeLayout.backgroundRect(imageSize: image, container: .zero, mode: .fitXY), .zero)
        XCTAssertEqual(ProfileThemeLayout.BackgroundMode("FIT_XY"), .fitXY)
        XCTAssertEqual(ProfileThemeLayout.BackgroundMode(nil), .centerCrop)
        XCTAssertEqual(ProfileThemeLayout.BackgroundMode("future_mode"), .centerCrop)

        // Downsampling must not shrink a native tile: raw source pixels divided
        // by screen scale, not the thumbnail's dimensions, set its display size.
        XCTAssertEqual(ProfileThemeLayout.tileScale(sourceSize: CGSize(width: 2400, height: 1200),
                                                    decodedSize: CGSize(width: 1200, height: 600), displayScale: 3),
                       2.0 / 3, accuracy: 0.001)
        XCTAssertEqual(ProfileThemeLayout.tileScale(sourceSize: image, decodedSize: image, displayScale: .nan), 1)
        XCTAssertEqual(ProfileThemeLayout.tileScale(sourceSize: .zero, decodedSize: image, displayScale: 3), 1)
    }

    func testParticleParametersMatchAndroidAndPositionsAreStable() throws {
        let normal = try layout()
        XCTAssertEqual(normal.density, 0.04)
        XCTAssertEqual(normal.pixelSizeRange, 40..<90)
        XCTAssertEqual(normal.speedMultiplier, 1)
        let high = try layout(#", "theme_icon_density":"HIGH", "theme_icon_size":"large", "theme_animation_speed":"ultra", "theme_icon_alpha":0.75"#)
        XCTAssertEqual(high.density, 0.07)
        XCTAssertEqual(high.pixelSizeRange, 70..<140)
        XCTAssertEqual(high.speedMultiplier, 50)
        let low = try layout(#", "theme_icon_density":"low", "theme_icon_size":"small", "theme_animation_speed":"medium""#)
        XCTAssertEqual(low.pixelSizeRange, 25..<55)
        XCTAssertEqual(low.speedMultiplier, 5)
        let ultra = try layout(#", "theme_icon_size":"ultra", "theme_animation_speed":"high""#)
        XCTAssertEqual(ultra.pixelSizeRange, 150..<250)
        XCTAssertEqual(ultra.speedMultiplier, 10)

        let size = CGSize(width: 360, height: 200)
        let first = high.particles(in: size, displayScale: 3)
        XCTAssertEqual(first, high.particles(in: size, displayScale: 3))
        XCTAssertEqual(first.count, 42)
        for particle in first {
            XCTAssertTrue((0..<size.width).contains(particle.origin.x))
            XCTAssertTrue((0..<size.height).contains(particle.origin.y))
            XCTAssertTrue((CGFloat(70) / 3..<CGFloat(140) / 3).contains(particle.size))
            XCTAssertTrue((0..<0.75).contains(particle.opacity))
            XCTAssertLessThanOrEqual(abs(particle.rotation), 30)
            XCTAssertLessThanOrEqual(abs(particle.velocity.dx), 250)
            XCTAssertLessThanOrEqual(abs(particle.velocity.dy), 250)
            XCTAssertLessThanOrEqual(abs(particle.rotationSpeed), 375)
        }
        let other = ProfileThemeLayout(theme: try profileTestDecode(ProfileTheme.self, #"{"id":8}"#))
        XCTAssertNotEqual(normal.particles(in: size, displayScale: 3), other.particles(in: size, displayScale: 3))
        XCTAssertTrue(normal.particles(in: .zero, displayScale: 3).isEmpty)
        XCTAssertTrue(normal.particles(in: CGSize(width: CGFloat.infinity, height: 200), displayScale: 3).isEmpty)
        XCTAssertEqual(normal.particles(in: CGSize(width: 360, height: 100_000), displayScale: 3).count, 256)
    }

    func testParticleWrapKeepsBothDirectionsInsideExtendedBounds() {
        let particle = ProfileThemeParticle(origin: CGPoint(x: 8, y: 4), rotation: 0, size: 2, opacity: 1,
                                            velocity: CGVector(dx: 3, dy: -4), rotationSpeed: 1)
        let size = CGSize(width: 10, height: 8)
        XCTAssertEqual(particle.position(at: 0, in: size), particle.origin)
        XCTAssertEqual(particle.position(at: -1, in: size), particle.origin)
        XCTAssertEqual(particle.position(at: .nan, in: size), particle.origin)
        XCTAssertEqual(particle.position(at: 2, in: size), CGPoint(x: 0, y: 8))
        for elapsed in stride(from: 0.0, through: 100.0, by: 0.25) {
            let position = particle.position(at: elapsed, in: size)
            XCTAssertTrue((-2..<12).contains(position.x))
            XCTAssertTrue((-2..<10).contains(position.y))
        }
    }

    func testFlatProfileThemeKeepsParticlePositionsAcrossUnrelatedRefreshes() throws {
        var profile = try profileTestDecode(Profile.self, #"{"id":42,"theme_enabled":true,"theme_icon_density":"high"}"#)
        let size = CGSize(width: 360, height: 200)
        let initial = ProfileThemeLayout(theme: profile.showcaseTheme).particles(in: size, displayScale: 3)
        profile.login = "Updated"
        profile.pinnedSectionId = ProfileSection.badges.rawValue
        XCTAssertEqual(initial, ProfileThemeLayout(theme: profile.showcaseTheme).particles(in: size, displayScale: 3))
        profile.id = 43
        XCTAssertNotEqual(initial, ProfileThemeLayout(theme: profile.showcaseTheme).particles(in: size, displayScale: 3))
    }

    func testAnimationPolicySeparatesGIFTimingFromParticlePreference() {
        for visible in [true, false] {
            for active in [true, false] {
                for reduced in [true, false] {
                    for particles in [true, false] {
                        let state = ProfileThemeAnimationState(isVisible: visible, isSceneActive: active,
                                                               reduceMotion: reduced, particleMotionEnabled: particles)
                        XCTAssertEqual(state.texturesRunning, visible && active && !reduced)
                        XCTAssertEqual(state.particlesRunning, visible && active && !reduced && particles)
                    }
                }
            }
        }
    }

    func testPausedClockResumesWithoutJumpingOrDoubleCounting() {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = ProfileThemeMotionClock()
        XCTAssertEqual(clock.elapsed(at: start), 0)
        clock.setRunning(true, at: start)
        clock.setRunning(true, at: start.addingTimeInterval(2))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(3)), 3)
        clock.setRunning(false, at: start.addingTimeInterval(3))
        clock.setRunning(false, at: start.addingTimeInterval(4))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(500)), 3)
        clock.setRunning(true, at: start.addingTimeInterval(500))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(502)), 5)
        clock.setRunning(false, at: start.addingTimeInterval(502))
        XCTAssertEqual(clock.accumulated, 5)
        XCTAssertNil(clock.startedAt)
    }

    func testGIFTimingUsesPerFrameDelaysAndSafeDefaults() {
        let timing = ProfileThemeFrameTiming(delays: [0.01, 0.02, 0.25, -1, .nan, .infinity, 900])
        let expected = [0.1, 0.12, 0.37, 0.47, 0.57, 0.67, 600.67]
        XCTAssertTrue(timing.isAnimated)
        for (actual, value) in zip(timing.ends, expected) { XCTAssertEqual(actual, value, accuracy: 0.0001) }
        XCTAssertEqual(timing.frame(at: -1), 0)
        XCTAssertEqual(timing.frame(at: .nan), 0)
        XCTAssertEqual(timing.frame(at: .infinity), 0)
        XCTAssertEqual(timing.frame(at: 0.099), 0)
        XCTAssertEqual(timing.frame(at: 0.1), 1)
        XCTAssertEqual(timing.frame(at: 0.121), 2)
        XCTAssertEqual(timing.frame(at: timing.duration), 0)
        XCTAssertEqual(timing.frame(at: timing.duration + 0.2), 2)
        XCTAssertFalse(ProfileThemeFrameTiming(delays: []).isAnimated)
        XCTAssertFalse(ProfileThemeFrameTiming(delays: [0.1]).isAnimated)
        XCTAssertEqual(ProfileThemeFrameTiming(delays: [0.1]).frame(at: 100), 0)
    }

    func testOnlyExactKnownAndroidArtworkNamesResolveLocally() {
        let resources = ["ic_heart", "ic_heart_outline", "ic_star_rate", "ic_stars", "ic_crown", "ic_bookmarks", "ic_bookmarks_filled"]
        let assets = resources.compactMap(ProfileThemeArtwork.name(for:))
        XCTAssertEqual(assets.count, 7)
        XCTAssertEqual(Set(assets).count, 7)
        XCTAssertEqual(ProfileThemeArtwork.name(for: "ic_heart"), "ProfileThemeHeart")
        for unknown in ["heart", "IC_HEART", "ic_heart_new", "ic_crown_outline", "unknown"] {
            XCTAssertNil(ProfileThemeArtwork.name(for: unknown))
        }
        XCTAssertNil(ProfileThemeArtwork.name(for: nil))
    }
}
