import Foundation
import Lottie
import AnixartKit

/// Lottie JSON is deliberately separate from ImageLoader: its ImageIO validation
/// rejects JSON. Decode off the main actor and share immutable models by URL.
actor ProfileBadgeAnimationLoader {
    static let shared = ProfileBadgeAnimationLoader()
    static let encodedByteLimit = 4 * 1024 * 1024
    static let cacheByteLimit = 16 * 1024 * 1024
    static let cacheCountLimit = 12

    private struct Loaded: Sendable {
        let animation: LottieAnimation
        let encodedByteCount: Int
    }

    private var cache: [URL: Loaded] = [:]
    private var order: [URL] = []
    private var inFlight: [URL: Task<Loaded?, Never>] = [:]
    private(set) var cachedByteCount = 0
    var cachedAnimationCount: Int { cache.count }
    private let fetchData: @Sendable (URL) async -> Data?

    init(fetchData: @escaping @Sendable (URL) async -> Data? = { await ProfileBadgeAnimationTransport.data(for: $0) }) {
        self.fetchData = fetchData
    }

    func animation(for url: URL) async -> LottieAnimation? {
        guard !Task.isCancelled, let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return nil }
        if let loaded = cache[url] {
            order.removeAll { $0 == url }
            order.append(url)
            return loaded.animation
        }
        if let task = inFlight[url] {
            let loaded = await task.value
            return Task.isCancelled ? nil : loaded?.animation
        }
        let fetch = fetchData
        let task = Task<Loaded?, Never>(priority: .utility) {
            let mirror = AnixartURL.mirrored(url)
            for candidate in (mirror == url ? [url] : [url, mirror]) {
                guard !Task.isCancelled else { return nil }
                guard let data = await fetch(candidate), let animation = Self.decode(data) else { continue }
                return Loaded(animation: animation, encodedByteCount: data.count)
            }
            return nil
        }
        inFlight[url] = task
        let loaded = await task.value
        inFlight[url] = nil
        if let loaded {
            while cache.count >= Self.cacheCountLimit || cachedByteCount + loaded.encodedByteCount > Self.cacheByteLimit {
                guard let oldest = order.first, let removed = cache.removeValue(forKey: oldest) else { break }
                order.removeFirst()
                cachedByteCount -= removed.encodedByteCount
            }
            cache[url] = loaded
            order.append(url)
            cachedByteCount += loaded.encodedByteCount
        }
        return Task.isCancelled ? nil : loaded?.animation
    }

    static func decode(_ data: Data) -> LottieAnimation? {
        guard !Task.isCancelled, !data.isEmpty, data.count <= encodedByteLimit,
              let animation = try? LottieAnimation.from(data: data, strategy: .legacyCodable),
              animation.size.width.isFinite, animation.size.height.isFinite,
              animation.size.width > 0, animation.size.height > 0,
              animation.size.width <= 4096, animation.size.height <= 4096,
              animation.framerate.isFinite, animation.framerate > 0,
              animation.startFrame.isFinite, animation.endFrame.isFinite,
              animation.endFrame > animation.startFrame,
              animation.duration.isFinite, animation.duration <= 600 else { return nil }
        return animation
    }
}

enum ProfileBadgeAnimationTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func data(for url: URL) async -> Data? {
        do {
            // Download to a temporary file first, so a large response is not
            // materialized in memory before checking the JSON byte limit.
            let (file, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            guard !Task.isCancelled, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  (1...ProfileBadgeAnimationLoader.encodedByteLimit).contains(size) else { return nil }
            return try Data(contentsOf: file, options: .mappedIfSafe)
        } catch { return nil }
    }
}
