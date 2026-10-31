import SwiftUI
import UIKit
import XCTest
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
        let resources = ["ic_heart", "ic_heart_outline", "ic_star_rate", "ic_stars", "ic_crown", "ic_bookmarks", "ic_bookmarks_filled"]
        for resource in resources {
            let asset = try XCTUnwrap(ProfileThemeArtwork.name(for: resource))
            let image = try XCTUnwrap(UIImage(named: asset, in: bundle, compatibleWith: nil), asset)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
            let canvas = Canvas { context, size in
                var resolved = context.resolve(Image(asset, bundle: bundle))
                resolved.shading = .color(.red)
                context.draw(resolved, in: CGRect(origin: .zero, size: size))
            }
            let pixels = try render(canvas, size: CGSize(width: 48, height: 48)).opaquePixels
            XCTAssertFalse(pixels.isEmpty, asset)
            XCTAssertTrue(pixels.allSatisfy { $0.red > 240 && $0.green < 15 && $0.blue < 15 }, asset)
        }
    }
}
