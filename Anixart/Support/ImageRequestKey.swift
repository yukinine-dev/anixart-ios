import CoreGraphics
import Foundation

/// URL and the actual, bounded decode size identify both cached and in-flight
/// images. A size change must not reuse a smaller thumbnail or an older task.
struct ImageRequestKey: Hashable, Sendable {
    let url: URL
    let pixelSize: Int

    init(url: URL, pixelSize: CGFloat, limit: Int = 4096) {
        self.url = url
        let size = pixelSize.isFinite ? pixelSize : 1200
        self.pixelSize = Int(min(CGFloat(limit), max(1, size)).rounded(.up))
    }

    var cacheKey: NSString {
        // Length-prefixing also keeps a URL's own fragment out of the size key.
        "\(url.absoluteString.utf8.count):\(url.absoluteString):\(pixelSize)" as NSString
    }
}
