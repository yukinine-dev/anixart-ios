import Foundation
import ImageIO
import UIKit
import XCTest
@testable import Anixart

final class ProfileThemeTextureTests: XCTestCase {
    private func url(_ name: String = "background") throws -> URL {
        try XCTUnwrap(URL(string: "https://theme-tests.invalid/\(name)"))
    }

    @MainActor
    func testGIFMetadataAndFramesAreDecodedLazily() async throws {
        let data = try ProfileThemeTestImages.gif(frameCount: 16, delays: [0.01, 0.02, 0.25])
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: data, pixelSize: 64))
        let before = await decoder.cachedFrameCount
        XCTAssertEqual(before, 0)
        let loaded = await decoder.sequence()
        let sequence = try XCTUnwrap(loaded)
        let firstCount = await decoder.cachedFrameCount
        let indices = await decoder.cachedFrameIndices
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(indices, [0])
        XCTAssertEqual(sequence.sourceSize, CGSize(width: 16, height: 8))
        XCTAssertEqual(sequence.timing.ends.count, 16)
        XCTAssertEqual(sequence.timing.ends[0], 0.1, accuracy: 0.001)
        XCTAssertEqual(sequence.timing.ends[1], 0.12, accuracy: 0.001)
        XCTAssertEqual(sequence.timing.ends[2], 0.37, accuracy: 0.001)
        XCTAssertEqual(sequence.cacheCost, data.count + ProfileThemeFrameDecoder.frameByteLimit)
        let frame = await sequence.frame(at: 5)
        XCTAssertNotNil(frame)
        let decodedCount = await decoder.cachedFrameCount
        XCTAssertEqual(decodedCount, 2)
        let first = await sequence.frame(at: 0)
        XCTAssertTrue(first === sequence.firstFrame)
    }

    @MainActor
    func testFrameLRUEvictsLeastRecentlyUsedFrameButPinsFirstFrame() async throws {
        let data = try ProfileThemeTestImages.gif(frameCount: 18)
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: data, pixelSize: 64))
        let loaded = await decoder.sequence()
        let sequence = try XCTUnwrap(loaded)
        for index in 1...11 { _ = await decoder.frame(at: index) }
        let full = await decoder.cachedFrameIndices
        XCTAssertEqual(full, Array(0...11))
        _ = await decoder.frame(at: 1)
        _ = await decoder.frame(at: 12)
        let evicted = await decoder.cachedFrameIndices
        XCTAssertEqual(evicted, [0] + Array(3...11) + [1, 12])
        for index in 13...17 {
            _ = await decoder.frame(at: index)
            let count = await decoder.cachedFrameCount
            let bytes = await decoder.cachedByteCount
            XCTAssertLessThanOrEqual(count, ProfileThemeFrameDecoder.frameCountLimit)
            XCTAssertLessThanOrEqual(bytes, ProfileThemeFrameDecoder.frameByteLimit)
        }
        let first = await decoder.frame(at: 0)
        XCTAssertTrue(first === sequence.firstFrame)
        let beforeInvalid = await decoder.cachedFrameIndices
        let negative = await decoder.frame(at: -1)
        let pastEnd = await decoder.frame(at: 18)
        let afterInvalid = await decoder.cachedFrameIndices
        XCTAssertNil(negative)
        XCTAssertNil(pastEnd)
        XCTAssertEqual(beforeInvalid, afterInvalid)
    }

    @MainActor
    func testFrameByteLimitEvictsBeforeCountLimitIsReached() async throws {
        let data = try ProfileThemeTestImages.gif(frameCount: 4, size: CGSize(width: 1400, height: 1400))
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: data, pixelSize: 1400))
        let loaded = await decoder.sequence()
        let sequence = try XCTUnwrap(loaded)
        let image = try XCTUnwrap(sequence.firstFrame.cgImage)
        let frameCost = image.bytesPerRow * image.height
        XCTAssertLessThanOrEqual(frameCost * 2, ProfileThemeFrameDecoder.frameByteLimit)
        XCTAssertGreaterThan(frameCost * 3, ProfileThemeFrameDecoder.frameByteLimit)
        for index in 1...3 {
            let frame = await decoder.frame(at: index)
            XCTAssertNotNil(frame)
            let indices = await decoder.cachedFrameIndices
            let bytes = await decoder.cachedByteCount
            XCTAssertEqual(indices, [0, index])
            XCTAssertLessThanOrEqual(bytes, ProfileThemeFrameDecoder.frameByteLimit)
        }
    }

    @MainActor
    func testPartialGIFFramesCompositeAndRespectDisposalInRandomAccessOrder() async throws {
        let loaded = await ProfileThemeTextureSequence.decode(ProfileThemeTestImages.compositingGIF, pixelSize: 64)
        let sequence = try XCTUnwrap(loaded)
        XCTAssertEqual(sequence.sourceSize, CGSize(width: 4, height: 4))
        XCTAssertEqual(sequence.timing.ends.count, 5)
        // Requesting the last frame first also checks that the image source does
        // not depend on this app having eagerly decoded all previous frames.
        for index in [4, 2, 1, 3, 0, 4] {
            let decoded = await sequence.frame(at: index)
            let pixels = try ProfileThemeTestPixels(XCTUnwrap(decoded))
            XCTAssertEqual(pixels.width, 4)
            XCTAssertEqual(pixels.height, 4)
            if index == 0 {
                assertProfileThemePixel(pixels, x: 0, y: 0, red: 255, green: 0, blue: 0)
            } else {
                assertProfileThemePixel(pixels, x: 0, y: 0, red: 0, green: 255, blue: 0)
            }
            if index == 2 {
                assertProfileThemePixel(pixels, x: 3, y: 0, red: 0, green: 0, blue: 255)
            } else if index >= 3 {
                XCTAssertLessThan(pixels.pixel(x: 3, y: 0).alpha, 15)
            } else {
                assertProfileThemePixel(pixels, x: 3, y: 0, red: 255, green: 0, blue: 0)
            }
            if index == 3 {
                assertProfileThemePixel(pixels, x: 3, y: 3, red: 255, green: 255, blue: 0)
            } else {
                assertProfileThemePixel(pixels, x: 3, y: 3, red: 255, green: 0, blue: 0)
            }
            assertProfileThemePixel(pixels, x: 0, y: 3, red: 255, green: 0, blue: 0)
        }
    }

    @MainActor
    func testEXIFOrientationChangesSourceSizeAndDecodedThumbnailTogether() async throws {
        for orientation in 1...8 {
            let data = try ProfileThemeTestImages.jpeg(orientation: orientation)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            XCTAssertEqual((properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation)
            let loaded = await ProfileThemeTextureSequence.decode(data, pixelSize: 4)
            let sequence = try XCTUnwrap(loaded)
            let rotated = (5...8).contains(orientation)
            XCTAssertEqual(sequence.sourceSize, rotated ? CGSize(width: 4, height: 8) : CGSize(width: 8, height: 4))
            XCTAssertEqual(sequence.firstFrame.size, rotated ? CGSize(width: 2, height: 4) : CGSize(width: 4, height: 2))
            XCTAssertFalse(sequence.timing.isAnimated)
            let frame = await sequence.frame(at: 0)
            XCTAssertTrue(frame === sequence.firstFrame)
        }
    }

    @MainActor
    func testLongAnimationsFallBackToFirstFrame() async throws {
        let data = try ProfileThemeTestImages.gif(frameCount: 1025, size: CGSize(width: 1, height: 1))
        let loaded = await ProfileThemeTextureSequence.decode(data, pixelSize: 1)
        let sequence = try XCTUnwrap(loaded)
        XCTAssertEqual(sequence.timing.ends.count, 1)
        XCTAssertFalse(sequence.timing.isAnimated)
        XCTAssertLessThan(sequence.cacheCost, data.count + ProfileThemeFrameDecoder.frameByteLimit)
    }

    func testInvalidAndOversizedEncodedDataAreRejected() async {
        for data in [Data(), Data("not an image".utf8), Data(repeating: 0, count: 32 * 1024 * 1024 + 1)] {
            let sequence = await ProfileThemeTextureSequence.decode(data, pixelSize: 64)
            XCTAssertNil(sequence)
        }
    }

    @MainActor
    func testLoaderSharesConcurrentRequestsAndKeepsResultAfterWaiterCancellation() async throws {
        let gate = ProfileTestGate()
        defer { gate.release() }
        let source = ProfileThemeTestDataSource(data: try ProfileThemeTestImages.png(), gate: gate)
        let loader = ProfileThemeTextureLoader { await source.fetch($0) }
        let url = try url()
        let cancelled = Task { await loader.sequence(for: url, pixelSize: 64) }
        defer { cancelled.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        let shared = Task { await loader.sequence(for: url, pixelSize: 64) }
        defer { shared.cancel() }
        cancelled.cancel()
        gate.release()
        let abandoned = await cancelled.value
        let loaded = await shared.value
        let sequence = try XCTUnwrap(loaded)
        let cached = await loader.sequence(for: url, pixelSize: 64)
        let requests = await source.requests
        XCTAssertNil(abandoned)
        XCTAssertTrue(cached === sequence)
        XCTAssertEqual(requests, [url])
    }

    @MainActor
    func testLoaderKeysIncludeDifferentURLsAndRoundedDecodeSizes() async throws {
        let source = ProfileThemeTestDataSource(data: try ProfileThemeTestImages.png())
        let loader = ProfileThemeTextureLoader { await source.fetch($0) }
        let firstURL = try url("a")
        let secondURL = try url("b")
        let first = await loader.sequence(for: firstURL, pixelSize: 12.2)
        let rounded = await loader.sequence(for: firstURL, pixelSize: 12.8)
        let resized = await loader.sequence(for: firstURL, pixelSize: 13.1)
        let other = await loader.sequence(for: secondURL, pixelSize: 12.2)
        let requests = await source.requests
        XCTAssertNotNil(first)
        XCTAssertTrue(first === rounded)
        XCTAssertFalse(first === resized)
        XCTAssertFalse(first === other)
        XCTAssertEqual(requests, [firstURL, firstURL, secondURL])
    }

    @MainActor
    func testLoaderDoesNotCacheTransportOrDecodeFailures() async throws {
        let source = ProfileThemeTestDataSource(data: nil)
        let loader = ProfileThemeTextureLoader { await source.fetch($0) }
        let url = try url()
        let missing = await loader.sequence(for: url, pixelSize: 64)
        await source.setResponse(Data("not an image".utf8))
        let malformed = await loader.sequence(for: url, pixelSize: 64)
        let failedCount = await loader.cachedSequenceCount
        let failedCost = await loader.cachedCost
        XCTAssertNil(missing)
        XCTAssertNil(malformed)
        XCTAssertEqual(failedCount, 0)
        XCTAssertEqual(failedCost, 0)
        await source.setResponse(try ProfileThemeTestImages.png())
        let loaded = await loader.sequence(for: url, pixelSize: 64)
        let cached = await loader.sequence(for: url, pixelSize: 64)
        let requests = await source.requests
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded === cached)
        XCTAssertEqual(requests.count, 3)
    }

    @MainActor
    func testSequenceCacheEvictsByRecencyAndCount() async throws {
        let source = ProfileThemeTestDataSource(data: try ProfileThemeTestImages.png())
        let loader = ProfileThemeTextureLoader { await source.fetch($0) }
        let urls = try (0..<5).map { try url("static-\($0)") }
        for url in urls.prefix(4) { _ = await loader.sequence(for: url, pixelSize: 64) }
        _ = await loader.sequence(for: urls[0], pixelSize: 64)
        _ = await loader.sequence(for: urls[4], pixelSize: 64)
        let count = await loader.cachedSequenceCount
        let cost = await loader.cachedCost
        XCTAssertEqual(count, ProfileThemeTextureLoader.countLimit)
        XCTAssertLessThanOrEqual(cost, ProfileThemeTextureLoader.costLimit)
        _ = await loader.sequence(for: urls[0], pixelSize: 64)
        let beforeMiss = await source.requests
        XCTAssertEqual(beforeMiss.count, 5)
        _ = await loader.sequence(for: urls[1], pixelSize: 64)
        let afterMiss = await source.requests
        XCTAssertEqual(afterMiss.count, 6)
        XCTAssertEqual(afterMiss.last, urls[1])
    }

    @MainActor
    func testSequenceCacheReservesAnimatedFrameMemoryBeforeCaching() async throws {
        let data = try ProfileThemeTestImages.gif(frameCount: 2)
        let source = ProfileThemeTestDataSource(data: data)
        let loader = ProfileThemeTextureLoader { await source.fetch($0) }
        let firstURL = try url("animated-a")
        let secondURL = try url("animated-b")
        let first = await loader.sequence(for: firstURL, pixelSize: 64)
        let loaded = await loader.sequence(for: secondURL, pixelSize: 64)
        let second = try XCTUnwrap(loaded)
        let count = await loader.cachedSequenceCount
        let cost = await loader.cachedCost
        XCTAssertNotNil(first)
        XCTAssertEqual(second.cacheCost, data.count + ProfileThemeFrameDecoder.frameByteLimit)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(cost, second.cacheCost)
        XCTAssertLessThanOrEqual(cost, ProfileThemeTextureLoader.costLimit)
        _ = await loader.sequence(for: firstURL, pixelSize: 64)
        let requests = await source.requests
        XCTAssertEqual(requests, [firstURL, secondURL, firstURL])
    }
}
