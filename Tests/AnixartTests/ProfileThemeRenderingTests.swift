import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileThemeRenderingTests: XCTestCase {
    @MainActor
    private func render<Content: View>(_ content: Content, size: CGSize) throws -> ProfileThemeTestPixels {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        return try ProfileThemeTestPixels(XCTUnwrap(renderer.uiImage))
    }

    @MainActor
    private func renderArtwork(_ image: Image, tint: Color?, size: CGSize, opacity: Double = 1) throws -> ProfileThemeTestPixels {
        let canvas = Canvas { context, size in
            let resolved = ProfileThemeArtwork.resolve(image, in: context)
            var layer = context
            layer.opacity = opacity
            ProfileThemeArtwork.draw(resolved, in: CGRect(origin: .zero, size: size), context: layer, tint: tint)
        }
        return try render(canvas, size: size)
    }

    @MainActor
    private func artworkBitmap() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 4, y: 0, width: 4, height: 4))
            UIColor.red.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 4, width: 4, height: 4))
        }
    }

    @MainActor
    func testShowcaseRendersFlatProfileThemeAndHonorsDisabledFlag() throws {
        for enabled in [true, false] {
            let profile = try profileTestDecode(Profile.self,
                "{\"id\":42,\"theme_enabled\":\(enabled),\"theme_gradient_start_color\":\"#FF0000\","
                    + "\"theme_gradient_end_color\":\"#FF0000\",\"theme_gradient_angle\":\"left_to_right\","
                    + "\"theme\":{\"id\":999,\"theme_enabled\":true,\"theme_gradient_start_color\":\"#00FF00\"}}")
            let showcase = ProfileBadgeShowcase(profile: profile, badges: [], viewer: nil)
                .environment(AppEnvironment.preview())
                .background(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1))
            let pixels = try render(showcase, size: CGSize(width: 64, height: 64))
            assertProfileThemePixel(pixels, x: 32, y: 32,
                                    red: enabled ? 255 : 0, green: 0, blue: enabled ? 0 : 255)
        }
    }

    @MainActor
    func testNativeTilesKeepTheirOriginalScaleAndTopLeftOrientation() throws {
        let image = ProfileThemeTestImages.bitmap()
        let fixture = try ProfileThemeTestPixels(image)
        assertProfileThemePixel(fixture, x: 0, y: 0, red: 255, green: 0, blue: 0)
        assertProfileThemePixel(fixture, x: 3, y: 0, red: 0, green: 255, blue: 0)
        assertProfileThemePixel(fixture, x: 0, y: 5, red: 0, green: 0, blue: 255)
        let size = CGSize(width: 24, height: 36)
        let native = try render(ProfileThemeBitmapDrawing(bitmap: image, sourceSize: CGSize(width: 8, height: 12),
                                                         mode: .tile, displayScale: 1), size: size)
        assertProfileThemePixel(native, x: 1, y: 1, red: 255, green: 0, blue: 0)
        assertProfileThemePixel(native, x: 5, y: 1, red: 0, green: 255, blue: 0)
        assertProfileThemePixel(native, x: 1, y: 7, red: 0, green: 0, blue: 255)
        assertProfileThemePixel(native, x: 5, y: 7, red: 255, green: 255, blue: 0)
        assertProfileThemePixel(native, x: 9, y: 13, red: 255, green: 0, blue: 0)

        let retina = try render(ProfileThemeBitmapDrawing(bitmap: image, sourceSize: CGSize(width: 8, height: 12),
                                                         mode: .tile, displayScale: 2), size: size)
        assertProfileThemePixel(retina, x: 0, y: 0, red: 255, green: 0, blue: 0)
        assertProfileThemePixel(retina, x: 3, y: 0, red: 0, green: 255, blue: 0)
        assertProfileThemePixel(retina, x: 0, y: 4, red: 0, green: 0, blue: 255)
        assertProfileThemePixel(retina, x: 3, y: 4, red: 255, green: 255, blue: 0)
        assertProfileThemePixel(retina, x: 4, y: 6, red: 255, green: 0, blue: 0)
    }

    @MainActor
    func testBitmapStretchUsesTheFullContainer() throws {
        let pixels = try render(ProfileThemeBitmapDrawing(bitmap: ProfileThemeTestImages.bitmap(), sourceSize: CGSize(width: 4, height: 6),
                                                         mode: .fitXY, displayScale: 1), size: CGSize(width: 16, height: 12))
        assertProfileThemePixel(pixels, x: 2, y: 2, red: 255, green: 0, blue: 0)
        assertProfileThemePixel(pixels, x: 13, y: 2, red: 0, green: 255, blue: 0)
        assertProfileThemePixel(pixels, x: 2, y: 9, red: 0, green: 0, blue: 255)
        assertProfileThemePixel(pixels, x: 13, y: 9, red: 255, green: 255, blue: 0)
    }

    @MainActor
    func testAllLocalSVGAssetsRenderAndAcceptCanvasTint() throws {
        let bundle = Bundle(for: AppEnvironment.self)
        let resources: [(name: String, red: Int, green: Int, blue: Int)] = [
            ("ic_heart", 0, 0, 0), ("ic_heart_outline", 0, 0, 0), ("ic_star_rate", 0, 0, 0),
            ("ic_stars", 117, 117, 117), ("ic_crown", 255, 193, 7),
            ("ic_bookmarks", 0, 0, 0), ("ic_bookmarks_filled", 0, 0, 0)
        ]
        for resource in resources {
            let asset = try XCTUnwrap(ProfileThemeArtwork.name(for: resource.name))
            let image = try XCTUnwrap(UIImage(named: asset, in: bundle, compatibleWith: nil), asset)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            let original = try renderArtwork(Image(asset, bundle: bundle), tint: nil,
                                             size: CGSize(width: 48, height: 48)).opaquePixels
            XCTAssertFalse(original.isEmpty, asset)
            let unexpectedOriginal = original.first {
                abs($0.red - resource.red) > 15 || abs($0.green - resource.green) > 15 || abs($0.blue - resource.blue) > 15
            }
            XCTAssertNil(unexpectedOriginal, "\(asset): unexpected original pixel \(String(describing: unexpectedOriginal))")
            let pixels = try renderArtwork(Image(asset, bundle: bundle),
                                           tint: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1),
                                           size: CGSize(width: 48, height: 48)).opaquePixels
            XCTAssertFalse(pixels.isEmpty, asset)
            let unexpected = pixels.first { $0.red <= 240 || $0.green >= 15 || $0.blue >= 15 }
            XCTAssertNil(unexpected, "\(asset): unexpected tinted pixel \(String(describing: unexpected))")
        }
    }

    @MainActor
    func testBitmapArtworkKeepsOriginalColorsWithoutTintAndMasksTintWithSourceAlpha() throws {
        let size = CGSize(width: 8, height: 8)
        let bitmap = artworkBitmap()
        let tints: [Color?] = [nil, Color(.sRGB, red: 0, green: 1, blue: 1, opacity: 1)]
        for tint in tints {
            let pixels = try renderArtwork(Image(uiImage: bitmap), tint: tint, size: size)
            assertProfileThemePixel(pixels, x: 1, y: 1, red: 0, green: 255, blue: tint == nil ? 0 : 255)
            assertProfileThemePixel(pixels, x: 6, y: 1, red: 0, green: tint == nil ? 0 : 255, blue: 255)
            let translucent = pixels.pixel(x: 1, y: 6)
            XCTAssertEqual(Double(translucent.alpha), 128, accuracy: 1)
            XCTAssertEqual(Double(translucent.red), tint == nil ? 128 : 0, accuracy: 1)
            XCTAssertEqual(Double(translucent.green), tint == nil ? 0 : 128, accuracy: 1)
            XCTAssertEqual(Double(translucent.blue), tint == nil ? 0 : 128, accuracy: 1)
            XCTAssertEqual(pixels.pixel(x: 6, y: 6).alpha, 0)
        }
    }

    @MainActor
    func testArtworkMaskPreservesTransformsAndAppliesParticleOpacityOnce() throws {
        let image = Image(uiImage: artworkBitmap())
        let tints: [Color?] = [nil, Color(.sRGB, red: 0, green: 1, blue: 1, opacity: 0.5)]
        for tint in tints {
            let canvas = Canvas { context, _ in
                let resolved = ProfileThemeArtwork.resolve(image, in: context)
                var particle = context
                particle.translateBy(x: 20, y: 4)
                particle.rotate(by: .degrees(90))
                particle.scaleBy(x: 2, y: 1)
                particle.opacity = 0.5
                ProfileThemeArtwork.draw(resolved, in: CGRect(x: 0, y: 0, width: 8, height: 8), context: particle, tint: tint)
                // Drawing after an icon must not inherit its private alpha mask.
                particle.fill(Path(CGRect(x: 8, y: 0, width: 2, height: 2)),
                              with: .color(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)))
            }
            let pixels = try render(canvas, size: CGSize(width: 24, height: 24))
            let samples: [(x: Int, y: Int, red: Int, green: Int, blue: Int, alpha: Int)] = [
                (18, 8, 0, tint == nil ? 128 : 64, tint == nil ? 0 : 64, tint == nil ? 128 : 64),
                (18, 16, 0, tint == nil ? 0 : 64, tint == nil ? 128 : 64, tint == nil ? 128 : 64),
                (14, 8, tint == nil ? 64 : 0, tint == nil ? 0 : 32, tint == nil ? 0 : 32, tint == nil ? 64 : 32),
                (14, 16, 0, 0, 0, 0), (3, 3, 0, 0, 0, 0), (19, 22, 0, 0, 128, 128)
            ]
            for sample in samples {
                let pixel = pixels.pixel(x: sample.x, y: sample.y)
                let message = "tinted=\(tint != nil), pixel (\(sample.x), \(sample.y))"
                XCTAssertEqual(Double(pixel.red), Double(sample.red), accuracy: 1, message)
                XCTAssertEqual(Double(pixel.green), Double(sample.green), accuracy: 1, message)
                XCTAssertEqual(Double(pixel.blue), Double(sample.blue), accuracy: 1, message)
                XCTAssertEqual(Double(pixel.alpha), Double(sample.alpha), accuracy: 1, message)
            }
        }
    }

    @MainActor
    func testSVGMaskAppliesTintAlphaAndParticleOpacityOnce() throws {
        let image = Image("ProfileThemeCrown", bundle: Bundle(for: AppEnvironment.self))
        let size = CGSize(width: 48, height: 48)
        let original = try renderArtwork(image, tint: nil, size: size)
        let tinted = try renderArtwork(image, tint: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5),
                                       size: size, opacity: 0.5)
        var checked = 0
        for y in 0..<original.height {
            for x in 0..<original.width where original.pixel(x: x, y: y).alpha == 255 {
                let pixel = tinted.pixel(x: x, y: y)
                XCTAssertEqual(Double(pixel.red), 64, accuracy: 1)
                XCTAssertEqual(pixel.green, 0)
                XCTAssertEqual(pixel.blue, 0)
                XCTAssertEqual(Double(pixel.alpha), 64, accuracy: 1)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 0)
        XCTAssertEqual(tinted.pixel(x: 0, y: 0).alpha, 0)
    }
}
