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
    private static let cache = URLCache(
        memoryCapacity: 32 * 1024 * 1024,
        diskCapacity: ImageCacheSettings.boundedLimit(UserDefaults.standard.object(forKey: ImageCacheSettings.storageKey) as? Int ?? ImageCacheSettings.defaultLimitMB) * 1024 * 1024,
        diskPath: "anixart-images"
    )
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
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
    private var generation = 0

    init() {
        // Roughly 120 posters at list size; the OS evicts under pressure anyway.
        decoded.countLimit = 240
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    func cacheUsage() -> Int { Self.cache.currentDiskUsage }

    func setCacheLimit(mebibytes: Int) {
        let limit = ImageCacheSettings.boundedLimit(mebibytes)
        UserDefaults.standard.set(limit, forKey: ImageCacheSettings.storageKey)
        Self.cache.diskCapacity = limit * 1024 * 1024
    }

    func clearCache() {
        generation += 1
        for task in inFlight.values { task.cancel() }
        for task in dataInFlight.values { task.cancel() }
        inFlight = [:]
        dataInFlight = [:]
        decoded.removeAllObjects()
        Self.cache.removeAllCachedResponses()
    }

    /// `pixelSize` is the longest edge in pixels, so the caller does the
    /// point-to-pixel conversion where the display scale is actually known.
    func image(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = ImageRequestKey(url: url, pixelSize: pixelSize)
        if let cached = decoded.object(forKey: key.cacheKey) { return cached }

        if let existing = inFlight[key] {
            let image = await existing.value
            return Task.isCancelled || existing.isCancelled ? nil : image
        }

        let generation = self.generation
        let task = Task<UIImage?, Never> {
            guard let data = await self.data(for: url) else { return nil }
            return Self.downsample(data, pixelSize: CGFloat(key.pixelSize))
        }
        inFlight[key] = task
        let image = await task.value
        guard generation == self.generation, !task.isCancelled else { return nil }
        inFlight[key] = nil

        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            decoded.setObject(image, forKey: key.cacheKey, cost: cost)
        }
        return Task.isCancelled ? nil : image
    }

    /// An explicit failed-image retry must not reuse a cached corrupt/HTML
    /// response or an older in-flight decode. Ordinary callers keep their cache
    /// policy and request coalescing; successful retries refill the bounded cache.
    func retryImage(for url: URL, pixelSize: CGFloat) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = ImageRequestKey(url: url, pixelSize: pixelSize)
        inFlight.removeValue(forKey: key)?.cancel()
        dataInFlight.removeValue(forKey: url)?.cancel()
        let generation = self.generation
        guard let data = await Self.fetchData(url, cachePolicy: .reloadIgnoringLocalCacheData),
              !Task.isCancelled, generation == self.generation,
              let image = Self.downsample(data, pixelSize: CGFloat(key.pixelSize)) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        decoded.setObject(image, forKey: key.cacheKey, cost: cost)
        return image
    }

    /// Theme GIFs use the same byte cache/mirror fallback as still images, but
    /// decode frames on demand. Concurrent requests share bytes, not thumbnails
    /// of different sizes.
    func data(for url: URL) async -> Data? {
        if let task = dataInFlight[url] {
            let data = await task.value
            return Task.isCancelled || task.isCancelled ? nil : data
        }
        let generation = self.generation
        let task = Task { await Self.fetchData(url) }
        dataInFlight[url] = task
        let data = await task.value
        guard generation == self.generation, !task.isCancelled else { return nil }
        dataInFlight[url] = nil
        return data
    }

    /// The poster host, then its mirror.
    ///
    /// `static.anixart.tv` is slow and sometimes unreachable depending on where
    /// the request comes from, and the API publishes `mirror-static.anixart.tv`
    /// for exactly that. One host is tried, then the other, rather than both at
    /// once: a race would double the load on a host that is already struggling.
    private static func fetchData(_ url: URL, cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad) async -> Data? {
        let mirror = AnixartURL.mirrored(url)
        for candidate in (mirror == url ? [url] : [url, mirror]) {
            do {
                let request = URLRequest(url: candidate, cachePolicy: cachePolicy)
                let (data, response) = try await session.data(for: request)
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
    static func downsample(_ data: Data, pixelSize: CGFloat) -> UIImage? {
        guard !Task.isCancelled, let source = PhotoImageDecoder.source(from: data) else { return nil }
        return PhotoImageDecoder.thumbnail(from: source, pixelSize: pixelSize)
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
                content(Image(uiImage: image).renderingMode(.original))
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
