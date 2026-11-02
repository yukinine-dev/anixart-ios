import ImageIO
import UIKit

/// One decode policy for still photos and lazily requested animation frames.
/// ImageIO handles the source profile and alpha; retain its CGImage instead of
/// redrawing into an untagged RGB buffer, flattening transparency, or applying
/// an appearance correction. This does not introduce an HDR/gain-map policy.
enum PhotoImageDecoder {
    static func source(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    static func thumbnail(from source: CGImageSource, at index: Int = 0, pixelSize: CGFloat) -> UIImage? {
        guard !Task.isCancelled, index >= 0, index < CGImageSourceGetCount(source),
              pixelSize.isFinite, pixelSize >= 1 else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ] as [CFString: Any] as CFDictionary
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, index, options),
              !Task.isCancelled else { return nil }
        // The thumbnail transform already applied EXIF orientation. Its size is
        // in pixels, so keep the existing scale of 1 rather than using the screen.
        return image(from: bitmap)
    }

    static func image(from bitmap: CGImage, scale: CGFloat = 1, orientation: UIImage.Orientation = .up) -> UIImage {
        // Original rendering is a presentation choice, not a pixel conversion.
        // Keep the bitmap's color space, component precision and alpha intact.
        UIImage(cgImage: bitmap, scale: scale, orientation: orientation).withRenderingMode(.alwaysOriginal)
    }
}
