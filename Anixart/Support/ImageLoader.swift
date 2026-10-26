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
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private let decoded = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        // Roughly 120 posters at list size; the OS evicts under pressure anyway.
        decoded.countLimit = 240
        decoded.totalCostLimit = 64 * 1024 * 1024
    }

    func image(for url: URL, maxPixelSize: CGFloat) async -> UIImage? {
        let key = cacheKey(url, maxPixelSize)
        if let cached = decoded.object(forKey: key) { return cached }

        if let existing = inFlight[url] { return await existing.value }

        let task = Task<UIImage?, Never> { [maxPixelSize] in
            do {
                let (data, _) = try await Self.session.data(from: url)
                return Self.downsample(data, maxPixelSize: maxPixelSize)
            } catch {
                Self.log.notice("image failed \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            decoded.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    private func cacheKey(_ url: URL, _ maxPixelSize: CGFloat) -> NSURL {
        // The same poster is drawn at a few sizes; each gets its own entry so a
        // grid thumbnail is never blown up into a detail header.
        (URL(string: "\(url.absoluteString)#\(Int(maxPixelSize))") ?? url) as NSURL
    }

    /// Decodes straight to the size that will be drawn. Full-size decoding is
    /// what makes a long list stutter, not the download.
    private static func downsample(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize * UIScreen.main.scale
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
            let loaded = await ImageLoader.shared.image(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedURL = url
        }
    }
}
