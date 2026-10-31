import ImageIO
import SwiftUI
import UIKit

/// GIF timing remains independent of the particle-motion preference, as in
/// Android. Both clocks are still paused off-screen and for Reduce Motion.
struct ProfileThemeFrameTiming: Equatable, Sendable {
    let ends: [TimeInterval]
    var duration: TimeInterval { ends.last ?? 0 }
    var isAnimated: Bool { ends.count > 1 && duration > 0 && duration.isFinite }

    init(delays: [TimeInterval]) {
        var total: TimeInterval = 0
        ends = delays.map { delay in
            // Glide also substitutes 100 ms for missing/very short GIF delays.
            total += delay.isFinite && delay >= 0.02 ? min(600, delay) : 0.1
            return total
        }
    }

    func frame(at elapsed: TimeInterval) -> Int {
        guard isAnimated, elapsed.isFinite, elapsed > 0 else { return 0 }
        let time = elapsed.truncatingRemainder(dividingBy: duration)
        var low = 0, high = ends.count - 1
        while low < high {
            let middle = (low + high) / 2
            if time < ends[middle] { high = middle }
            else { low = middle + 1 }
        }
        return low
    }
}

/// Immutable metadata and first frame. ImageIO and the bounded frame cache live
/// in a separate actor; the UI never eagerly decodes a whole background GIF.
final class ProfileThemeTextureSequence: @unchecked Sendable {
    let firstFrame: UIImage
    let sourceSize: CGSize
    let timing: ProfileThemeFrameTiming
    /// Encoded bytes plus a reservation for all frames this decoder may retain,
    /// not just the first frame visible when the sequence enters the cache.
    let cacheCost: Int
    private let decoder: ProfileThemeFrameDecoder

    fileprivate init(firstFrame: UIImage, sourceSize: CGSize, timing: ProfileThemeFrameTiming,
                     cacheCost: Int, decoder: ProfileThemeFrameDecoder) {
        self.firstFrame = firstFrame
        self.sourceSize = sourceSize
        self.timing = timing
        self.cacheCost = cacheCost
        self.decoder = decoder
    }

    static func decode(_ data: Data, pixelSize: CGFloat) async -> ProfileThemeTextureSequence? {
        guard !Task.isCancelled, !data.isEmpty, data.count <= 32 * 1024 * 1024,
              let decoder = ProfileThemeFrameDecoder(data: data, pixelSize: pixelSize) else { return nil }
        return await decoder.sequence()
    }

    func frame(at index: Int) async -> UIImage? { await decoder.frame(at: index) }
}

actor ProfileThemeFrameDecoder {
    static let frameCountLimit = 12
    static let frameByteLimit = 16 * 1024 * 1024
    private let source: CGImageSource
    private let pixelSize: CGFloat
    private let encodedByteCount: Int
    private var firstFrame: UIImage?
    private var frames: [Int: UIImage] = [:]
    private var order: [Int] = []
    private(set) var cachedByteCount = 0
    var cachedFrameCount: Int { frames.count + (firstFrame == nil ? 0 : 1) }
    var cachedFrameIndices: [Int] { (firstFrame == nil ? [] : [0]) + order }

    init?(data: Data, pixelSize: CGFloat) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        self.source = source
        self.pixelSize = pixelSize.isFinite ? min(2048, max(1, pixelSize)) : 1200
        self.encodedByteCount = data.count
    }

    func sequence() -> ProfileThemeTextureSequence? {
        guard let image = frame(at: 0) else { return nil }
        let count = CGImageSourceGetCount(source)
        // Malformed or unusually long animations fall back to their still frame.
        let safeCount = (1...1024).contains(count) ? count : 1
        var delays: [TimeInterval] = []
        for index in 0..<safeCount {
            guard !Task.isCancelled else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            delays.append((gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let rawHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        var width = rawWidth.isFinite && rawWidth > 0 ? rawWidth : Double(image.size.width)
        var height = rawHeight.isFinite && rawHeight > 0 ? rawHeight : Double(image.size.height)
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) { swap(&width, &height) }
        let timing = ProfileThemeFrameTiming(delays: delays)
        let cost = encodedByteCount + (timing.isAnimated ? max(cachedByteCount, Self.frameByteLimit) : cachedByteCount)
        return ProfileThemeTextureSequence(firstFrame: image, sourceSize: CGSize(width: width, height: height),
                                           timing: timing, cacheCost: cost, decoder: self)
    }

    func frame(at index: Int) -> UIImage? {
        guard !Task.isCancelled, index >= 0, index < CGImageSourceGetCount(source) else { return nil }
        if index == 0, let firstFrame { return firstFrame }
        if let image = frames[index] {
            order.removeAll { $0 == index }
            order.append(index)
            return image
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ] as [CFString: Any] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, index, options), !Task.isCancelled else { return nil }
        let image = UIImage(cgImage: thumbnail)
        let cost = thumbnail.bytesPerRow * thumbnail.height
        if index == 0 {
            firstFrame = image
            cachedByteCount += cost
        } else if cost <= Self.frameByteLimit - (firstFrame?.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) {
            // NSCache's limits are advisory. Use a deterministic LRU for a hard
            // frame bound while keeping the sequence's first frame available.
            while frames.count + 2 > Self.frameCountLimit || cachedByteCount + cost > Self.frameByteLimit {
                guard let oldest = order.first, let removed = frames.removeValue(forKey: oldest) else { break }
                order.removeFirst()
                cachedByteCount -= removed.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            }
            frames[index] = image
            order.append(index)
            cachedByteCount += cost
        }
        return image
    }
}

actor ProfileThemeTextureLoader {
    static let shared = ProfileThemeTextureLoader()
    static let countLimit = 4
    static let costLimit = 32 * 1024 * 1024
    private var cache: [ImageRequestKey: ProfileThemeTextureSequence] = [:]
    private var order: [ImageRequestKey] = []
    private(set) var cachedCost = 0
    var cachedSequenceCount: Int { cache.count }
    private var inFlight: [ImageRequestKey: Task<ProfileThemeTextureSequence?, Never>] = [:]
    private let fetchData: @Sendable (URL) async -> Data?

    init(fetchData: @escaping @Sendable (URL) async -> Data? = { await ImageLoader.shared.data(for: $0) }) {
        self.fetchData = fetchData
    }

    func sequence(for url: URL, pixelSize: CGFloat) async -> ProfileThemeTextureSequence? {
        guard !Task.isCancelled else { return nil }
        let key = ImageRequestKey(url: url, pixelSize: pixelSize, limit: 2048)
        if let sequence = cache[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return sequence
        }
        if let task = inFlight[key] {
            let sequence = await task.value
            return Task.isCancelled ? nil : sequence
        }
        let task = Task<ProfileThemeTextureSequence?, Never>(priority: .utility) {
            guard let data = await fetchData(url) else { return nil }
            return await ProfileThemeTextureSequence.decode(data, pixelSize: CGFloat(key.pixelSize))
        }
        inFlight[key] = task
        let sequence = await task.value
        inFlight[key] = nil
        if let sequence, sequence.cacheCost <= Self.costLimit {
            while cache.count >= Self.countLimit || cachedCost + sequence.cacheCost > Self.costLimit {
                guard let oldest = order.first, let removed = cache.removeValue(forKey: oldest) else { break }
                order.removeFirst()
                cachedCost -= removed.cacheCost
            }
            cache[key] = sequence
            order.append(key)
            cachedCost += sequence.cacheCost
        }
        return Task.isCancelled ? nil : sequence
    }
}

@MainActor
struct ProfileThemeTexture<Content: View, Placeholder: View>: View {
    let url: URL
    /// Longest decoded edge in raw pixels, not points.
    let pixelSize: CGFloat
    let isAnimating: Bool
    @ViewBuilder var content: (UIImage, CGSize) -> Content
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var sequence: ProfileThemeTextureSequence?
    @State private var image: UIImage?
    @State private var loadedKey: ImageRequestKey?
    @State private var isVisible = false
    @State private var clock = ProfileThemeMotionClock()

    private var textureKey: ImageRequestKey { ImageRequestKey(url: url, pixelSize: pixelSize, limit: 2048) }
    private struct FrameKey: Equatable { let texture: ImageRequestKey; let index: Int; let running: Bool }

    var body: some View {
        let key = textureKey
        let currentSequence = loadedKey == key ? sequence : nil
        let running = isVisible && isAnimating && currentSequence?.timing.isAnimated == true
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            let index = currentSequence?.timing.frame(at: clock.elapsed(at: timeline.date)) ?? 0
            Group {
                if let image, loadedKey == key { content(image, currentSequence?.sourceSize ?? image.size) }
                else { placeholder() }
            }
            .task(id: FrameKey(texture: key, index: index, running: running)) {
                // A pause changes the task ID, cancelling any queued frame work.
                guard running, let sequence = currentSequence else { return }
                let frame = await sequence.frame(at: index)
                guard !Task.isCancelled, key == textureKey, sequence === self.sequence else { return }
                if let frame { image = frame }
            }
        }
        .task(id: key) {
            guard !Task.isCancelled, key == textureKey else { return }
            sequence = nil
            image = nil
            loadedKey = nil
            clock = ProfileThemeMotionClock()
            let loaded = await ProfileThemeTextureLoader.shared.sequence(for: key.url, pixelSize: CGFloat(key.pixelSize))
            guard !Task.isCancelled, key == textureKey else { return }
            sequence = loaded
            image = loaded?.firstFrame
            loadedKey = key
        }
        .onAppear { isVisible = true }
        .onChange(of: running) { _, running in clock.setRunning(running, at: Date()) }
        .onDisappear { isVisible = false; clock.setRunning(false, at: Date()) }
    }
}
