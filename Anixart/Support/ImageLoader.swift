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

    private let decoded = NSCache<NSString, UIImage>()
    private var inFlight: [ImageRequestKey: Task<UIImage?, Never>] = [:]
    private var dataInFlight: [URL: Task<Data?, Never>] = [:]

    init() {
        // Roughly 120 posters at list size; the OS evicts under pressure anyway.
        decoded.countLimit = 240
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    /// `pixelSize` is the longest edge in pixels, so the caller does the
    /// point-to-pixel conversion where the display scale is actually known.
    func image(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = ImageRequestKey(url: url, pixelSize: pixelSize)
        if let cached = decoded.object(forKey: key.cacheKey) { return cached }

        if let existing = inFlight[key] {
            let image = await existing.value
            return Task.isCancelled ? nil : image
        }

        let task = Task<UIImage?, Never> {
            guard let data = await self.data(for: url) else { return nil }
            return Self.downsample(data, pixelSize: CGFloat(key.pixelSize))
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            decoded.setObject(image, forKey: key.cacheKey, cost: cost)
        }
        return Task.isCancelled ? nil : image
    }

    /// Theme GIFs use the same byte cache/mirror fallback as still images, but
    /// decode frames on demand. Concurrent requests share bytes, not thumbnails
    /// of different sizes.
    func data(for url: URL) async -> Data? {
        if let task = dataInFlight[url] { return await task.value }
        let task = Task { await Self.fetchData(url) }
        dataInFlight[url] = task
        let data = await task.value
        dataInFlight[url] = nil
        return data
    }

    /// The poster host, then its mirror.
    ///
    /// `static.anixart.tv` is slow and sometimes unreachable depending on where
    /// the request comes from, and the API publishes `mirror-static.anixart.tv`
    /// for exactly that. One host is tried, then the other, rather than both at
    /// once: a race would double the load on a host that is already struggling.
    private static func fetchData(_ url: URL) async -> Data? {
        let mirror = AnixartURL.mirrored(url)
        for candidate in (mirror == url ? [url] : [url, mirror]) {
            do {
                let (data, response) = try await session.data(from: candidate)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    continue
                }
                guard CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else { continue }
                return data
            } catch {
                log.notice("image failed \(candidate.host() ?? "?", privacy: .public)\(candidate.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
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
    @State private var loadedKey: ImageRequestKey?

    private var requestKey: ImageRequestKey? {
        guard let url else { return nil }
        let scale = displayScale.isFinite ? max(1, displayScale) : 1
        return ImageRequestKey(url: url, pixelSize: maxPixelSize * scale)
    }

    var body: some View {
        Group {
            if let image, loadedKey == requestKey {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: requestKey) {
            guard let key = requestKey else {
                image = nil
                loadedKey = nil
                return
            }
            guard key != loadedKey || image == nil else { return }
            image = nil
            loadedKey = nil
            let loaded = await ImageLoader.shared.image(for: key.url, pixelSize: CGFloat(key.pixelSize))
            guard !Task.isCancelled, key == requestKey else { return }
            image = loaded
            loadedKey = key
        }
    }
}
