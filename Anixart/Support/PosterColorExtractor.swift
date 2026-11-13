import CoreImage
import SwiftUI
import UIKit

/// The top and bottom average colors of a poster, for the gradient tint
/// Android's `ReleaseBackdropTint` paints behind the release header -- that
/// backdrop has no blur, just a gradient pulled from the artwork's own colors.
struct PosterTint: Equatable {
    var top: Color
    var bottom: Color

    static let neutral = PosterTint(top: Color(white: 0.16), bottom: Color(white: 0.08))
}

enum PosterColorExtractor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Samples the top and bottom thirds of `image` with `CIAreaAverage`, the
    /// same cheap single-pixel reduction `Palette`/Glide-style extraction uses.
    /// `image` should already be a small thumbnail -- this does no downsampling
    /// of its own.
    static func tint(of image: UIImage) -> PosterTint {
        guard let cgImage = image.cgImage else { return .neutral }
        let ciImage = CIImage(cgImage: cgImage)
        let top = average(of: ciImage, in: CGRect(x: 0, y: 0, width: 1, height: 1.0 / 3))
        let bottom = average(of: ciImage, in: CGRect(x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3))
        return PosterTint(top: top ?? PosterTint.neutral.top, bottom: bottom ?? PosterTint.neutral.bottom)
    }

    /// `unitRect` is top-down (y=0 at the visual top), matching `UIImage`'s own
    /// convention; Core Image's extent is bottom-up, so y is flipped here.
    private static func average(of image: CIImage, in unitRect: CGRect) -> Color? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let region = CGRect(
            x: extent.minX + unitRect.minX * extent.width,
            y: extent.minY + (1 - unitRect.maxY) * extent.height,
            width: unitRect.width * extent.width,
            height: unitRect.height * extent.height
        ).intersection(extent)
        guard !region.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage",
                                     parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: region)]),
              let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                        format: .RGBA8, colorSpace: nil)
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
