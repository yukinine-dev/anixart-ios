import AnixartKit
import ImageIO
import SwiftUI
import UIKit
import os

/// Image loading for the lists.
///
/// `AsyncImage` refetches and re-decodes on every appearance and keeps nothing
/// between them, so scrolling a catalogue hammers the image host and decodes
/// the same poster again and again. Anixart's image host is not fast, which is
/// what made covers crawl in.
///
/// This keeps decoded images in memory, lets `URLCache` keep the bytes on disk
/// across launches, downsamples to the size actually drawn, and collapses
/// concurrent requests for the same URL into one.
actor ImageLoader {
    static let shared = ImageLoader()

    private static let log = Logger(subsystem: "app.anixart.client", category: "images")

    /// Bytes on disk and in memory, shared with everything using this session.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "anixart-images"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // The host is slow enough that a stampede makes it slower.
        configuration.httpMaximumConnectionsPerHost = 6
        // Short enough that the mirror is tried while the user is still looking
        // at the screen.
        configuration.timeoutIntervalForRequest = 12
        return URLSession(configuration: configuration)
    }()

    private let decoded = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        // Roughly 120 posters at list size; the OS evicts under pressure anyway.
        decoded.countLimit = 240
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    /// `pixelSize` is the longest edge in pixels, so the caller does the
    /// point-to-pixel conversion where the display scale is actually known.
    func image(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        let key = cacheKey(url, pixelSize)
        if let cached = decoded.object(forKey: key) { return cached }

        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [pixelSize] in
            await Self.fetch(url, pixelSize: pixelSize)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            decoded.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// The poster host, then its mirror.
    ///
    /// `static.anixart.tv` is slow and sometimes unreachable depending on where
    /// the request comes from, and the API publishes `mirror-static.anixart.tv`
    /// for exactly that. One host is tried, then the other, rather than both at
    /// once: a race would double the load on a host that is already struggling.
    private static func fetch(_ url: URL, pixelSize: CGFloat) async -> UIImage? {
        let mirror = AnixartURL.mirrored(url)
        for candidate in (mirror == url ? [url] : [url, mirror]) {
            do {
                let (data, response) = try await session.data(from: candidate)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continue
                }
                if let image = downsample(data, pixelSize: pixelSize) { return image }
            } catch {
                log.notice("image failed \(candidate.host() ?? "?", privacy: .public)\(candidate.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    private func cacheKey(_ url: URL, _ pixelSize: CGFloat) -> NSURL {
        // The same poster is drawn at a few sizes; each gets its own entry so a
        // grid thumbnail is never blown up into a detail header.
        (URL(string: "\(url.absoluteString)#\(Int(pixelSize))") ?? url) as NSURL
    }

    /// Decodes straight to the size that will be drawn. Full-size decoding is
    /// what makes a long list stutter, not the download.
    private static func downsample(_ data: Data, pixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ] as [CFString: Any] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

/// Drop-in for `AsyncImage` that goes through `ImageLoader`.
@MainActor
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    /// The longest edge this will be drawn at, in points.
    var maxPixelSize: CGFloat = 400
    @ViewBuilder var content: (Image) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale

    @State private var image: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            guard url != loadedURL else { return }
            let pixels = maxPixelSize * max(displayScale, 1)
            let loaded = await ImageLoader.shared.image(for: url, pixelSize: pixels)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedURL = url
        }
    }
}
