import SwiftUI
import UIKit
import XCTest
@testable import Anixart

final class PosterColorExtractorTests: XCTestCase {
    /// A top half of solid red over a bottom half of solid blue -- the gradient
    /// should pick up each half from the half it actually sits in, not an
    /// average of the whole poster or the halves swapped.
    func testTintSamplesTopAndBottomSeparately() throws {
        let image = try XCTUnwrap(Self.halves(top: .red, bottom: .blue))
        let tint = PosterColorExtractor.tint(of: image)
        XCTAssertTrue(Self.isClose(tint.top, .red), "top sample should read red, not \(tint.top)")
        XCTAssertTrue(Self.isClose(tint.bottom, .blue), "bottom sample should read blue, not \(tint.bottom)")
    }

    func testOpaqueSolidColorSamplesAsItself() throws {
        let image = try XCTUnwrap(Self.halves(top: .green, bottom: .green))
        let tint = PosterColorExtractor.tint(of: image)
        XCTAssertTrue(Self.isClose(tint.top, .green))
        XCTAssertTrue(Self.isClose(tint.bottom, .green))
    }

    private static func halves(top: UIColor, bottom: UIColor) -> UIImage? {
        let size = CGSize(width: 8, height: 60)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            top.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            bottom.setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        }
    }

    private static func isClose(_ color: Color, _ expected: UIColor, tolerance: CGFloat = 0.12) -> Bool {
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        let resolved = UIColor(color).cgColor.components ?? []
        guard resolved.count >= 3 else { return false }
        return abs(resolved[0] - er) < tolerance && abs(resolved[1] - eg) < tolerance && abs(resolved[2] - eb) < tolerance
    }
}
