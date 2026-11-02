import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Anixart

/// Local bitmap/profile assertions, not screenshots or requests to an avatar host.
final class AvatarColorTests: XCTestCase {
    @MainActor
    func testStillAndLargeAvatarPreserveSRGBMidtonesAndTransparency() async throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        // RGBA is premultiplied: the fifth pixel has real color at half alpha,
        // while the last pixel is transparent, not an opaque black matte.
        let samples: [UInt8] = [
            128, 128, 128, 255, 192, 80, 48, 255, 32, 96, 208, 255,
            0, 0, 0, 255, 80, 40, 20, 128, 0, 0, 0, 0
        ]
        let bitmap = try AvatarColorFixtures.bitmap(samples, space: space)
        let data = try AvatarColorFixtures.png(bitmap)
        let images = try await decodeBothAvatarPaths(data, pixelSize: 6)
        for image in images {
            assertOriginal(image)
            let decoded = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(decoded.width, 6)
            XCTAssertEqual(decoded.height, 1)
            assertBytes(try AvatarColorFixtures.rgba(decoded, space: space), equalTo: samples)
            // The compositing background is a display concern. Neither path may
            // bake black or white into the stored transparent photograph.
            for background in [CGFloat(0), CGFloat(1)] {
                assertBytes(try AvatarColorFixtures.rgba(decoded, space: space, background: background),
                            equalTo: try AvatarColorFixtures.rgba(bitmap, space: space, background: background))
            }
        }
    }

    @MainActor
    func testEmbeddedDisplayP3ICCPreservesGamutAndColorManagedSamples() async throws {
        let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let profile = try XCTUnwrap(p3.copyICCData())
        let iccSpace = try XCTUnwrap(CGColorSpace(iccData: profile))
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let samples: [UInt8] = [208, 72, 32, 255, 128, 128, 128, 255]
        let bitmap = try AvatarColorFixtures.bitmap(samples, space: iccSpace)
        let data = try AvatarColorFixtures.png(bitmap)
        let reference = try AvatarColorFixtures.encodedBitmap(data)
        let embedded = try XCTUnwrap(reference.colorSpace)
        XCTAssertTrue(embedded.isWideGamutRGB, "The local fixture must contain a wide-gamut profile.")
        XCTAssertNotNil(embedded.copyICCData())

        let managedSRGB = try AvatarColorFixtures.rgba(bitmap, space: sRGB)
        let incorrectlyRetagged = try AvatarColorFixtures.bitmap(samples, space: sRGB)
        let unmanagedSRGB = try AvatarColorFixtures.rgba(incorrectlyRetagged, space: sRGB)
        XCTAssertGreaterThan(abs(Int(managedSRGB[0]) - Int(unmanagedSRGB[0])), 8,
                             "The fixture must distinguish ICC conversion from merely relabeling RGB bytes.")
        let images = try await decodeBothAvatarPaths(data, pixelSize: 2)
        for image in images {
            assertOriginal(image)
            let decoded = try XCTUnwrap(image.cgImage)
            let decodedSpace = try XCTUnwrap(decoded.colorSpace)
            XCTAssertEqual(decodedSpace.model, .rgb)
            XCTAssertTrue(decodedSpace.isWideGamutRGB)
            XCTAssertNotNil(decodedSpace.copyICCData())
            assertBytes(try AvatarColorFixtures.rgba(decoded, space: iccSpace), equalTo: samples)
            assertBytes(try AvatarColorFixtures.rgba(decoded, space: sRGB), equalTo: managedSRGB)
        }
    }

    @MainActor
    func testLinearSRGBICCIsNotReinterpretedAsNonlinearSRGB() async throws {
        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let profile = try XCTUnwrap(linear.copyICCData())
        let iccSpace = try XCTUnwrap(CGColorSpace(iccData: profile))
        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let samples: [UInt8] = [64, 128, 192, 255, 16, 16, 16, 255]
        let bitmap = try AvatarColorFixtures.bitmap(samples, space: iccSpace)
        let data = try AvatarColorFixtures.png(bitmap)
        let reference = try AvatarColorFixtures.encodedBitmap(data)
        XCTAssertNotNil(try XCTUnwrap(reference.colorSpace).copyICCData())
        let managedSRGB = try AvatarColorFixtures.rgba(bitmap, space: sRGB)
        XCTAssertGreaterThan(Int(managedSRGB[0]) - Int(samples[0]), 50)
        let images = try await decodeBothAvatarPaths(data, pixelSize: 2)
        for image in images {
            assertOriginal(image)
            let decoded = try XCTUnwrap(image.cgImage)
            assertBytes(try AvatarColorFixtures.rgba(decoded, space: iccSpace), equalTo: samples)
            assertBytes(try AvatarColorFixtures.rgba(decoded, space: sRGB), equalTo: managedSRGB)
        }
    }

    func testOriginalWrapperRetainsExtendedRangeBitmapScaleAndOrientation() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        let components: [Float] = [1.5, 0.375, 0.125, 0.5]
        let data = components.withUnsafeBytes { Data($0) }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        let bitmap = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 32,
                                          bitsPerPixel: 128, bytesPerRow: 16, space: space,
                                          bitmapInfo: info, provider: provider, decode: nil,
                                          shouldInterpolate: false, intent: .relativeColorimetric))
        XCTAssertEqual(UIImage(cgImage: bitmap).renderingMode, .automatic)
        let image = PhotoImageDecoder.image(from: bitmap, scale: 3, orientation: .leftMirrored)
        let retained = try XCTUnwrap(image.cgImage)
        XCTAssertTrue(retained === bitmap, "Original rendering must not rasterize, retag or tone-map the bitmap.")
        XCTAssertEqual(image.renderingMode, .alwaysOriginal)
        XCTAssertEqual(image.scale, 3)
        XCTAssertEqual(image.imageOrientation, .leftMirrored)
        XCTAssertEqual(retained.bitsPerComponent, 32)
        XCTAssertTrue(retained.bitmapInfo.contains(.floatComponents))
        XCTAssertEqual(retained.alphaInfo, .premultipliedLast)
        XCTAssertTrue(CFEqual(try XCTUnwrap(retained.colorSpace), space))
        XCTAssertEqual(try XCTUnwrap(retained.dataProvider?.data) as Data, data)
        // This checks preservation of an already-decoded extended-range bitmap,
        // not ImageIO's handling of a HEIF/JPEG container's auxiliary HDR gain map.
    }

    @MainActor
    func testGIFOriginalRenderingKeepsPartialFrameAlphaAndLazyCache() async throws {
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: ProfileThemeTestImages.compositingGIF, pixelSize: 4))
        let before = await decoder.cachedFrameCount
        XCTAssertEqual(before, 0)
        let loaded = await decoder.sequence()
        let sequence = try XCTUnwrap(loaded)
        assertOriginal(sequence.firstFrame)
        XCTAssertEqual(sequence.timing.ends.count, 5)
        let firstCount = await decoder.cachedFrameCount
        XCTAssertEqual(firstCount, 1)

        let sRGB = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        // Request a later composited frame first; decoding must not start
        // retaining every earlier frame merely to make original-rendering images.
        for index in [4, 2] {
            let loadedFrame = await decoder.frame(at: index)
            let frame = try XCTUnwrap(loadedFrame)
            assertOriginal(frame)
            let pixels = try AvatarColorFixtures.rgba(XCTUnwrap(frame.cgImage), space: sRGB)
            assertBytes(Array(pixels[0..<4]), equalTo: [0, 255, 0, 255])
            assertBytes(Array(pixels[12..<16]), equalTo: index == 2 ? [0, 0, 255, 255] : [0, 0, 0, 0])
            let bytes = await decoder.cachedByteCount
            XCTAssertLessThanOrEqual(bytes, ProfileThemeFrameDecoder.frameByteLimit)
        }
        let indices = await decoder.cachedFrameIndices
        XCTAssertEqual(indices, [0, 4, 2])
        let first = await decoder.frame(at: 0)
        XCTAssertTrue(first === sequence.firstFrame)
    }

    @MainActor
    func testBothDecodePathsApplyEXIFOnceAndKeepPixelScale() async throws {
        for orientation in 1...8 {
            let data = try ProfileThemeTestImages.jpeg(orientation: orientation)
            let images = try await decodeBothAvatarPaths(data, pixelSize: 4)
            let expectedSize = (5...8).contains(orientation) ? CGSize(width: 2, height: 4) : CGSize(width: 4, height: 2)
            for image in images {
                assertOriginal(image)
                XCTAssertEqual(image.size, expectedSize)
            }
        }
    }

    @MainActor
    func testCancelledDecodesDoNotPopulateFrameCache() async throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let data = try AvatarColorFixtures.png(AvatarColorFixtures.bitmap([128, 64, 32, 255], space: space))
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: data, pixelSize: 1))
        let stillTask = Task { () -> UIImage? in
            withUnsafeCurrentTask { $0?.cancel() }
            return ImageLoader.downsample(data, pixelSize: 1)
        }
        let frameTask = Task { () -> UIImage? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await decoder.frame(at: 0)
        }
        let still = await stillTask.value
        let frame = await frameTask.value
        let cachedCount = await decoder.cachedFrameCount
        let cachedBytes = await decoder.cachedByteCount
        XCTAssertNil(still)
        XCTAssertNil(frame)
        XCTAssertEqual(cachedCount, 0)
        XCTAssertEqual(cachedBytes, 0)
    }

    func testMalformedLocalStillDataIsRejected() {
        for data in [Data(), Data("not an image".utf8)] {
            XCTAssertNil(ImageLoader.downsample(data, pixelSize: 44))
        }
    }

    @MainActor
    private func decodeBothAvatarPaths(_ data: Data, pixelSize: CGFloat) async throws -> [UIImage] {
        let smallAvatar = try XCTUnwrap(ImageLoader.downsample(data, pixelSize: pixelSize))
        let decoder = try XCTUnwrap(ProfileThemeFrameDecoder(data: data, pixelSize: pixelSize))
        let loaded = await decoder.sequence()
        let largeAvatar = try XCTUnwrap(loaded)
        let count = await decoder.cachedFrameCount
        XCTAssertEqual(count, 1)
        XCTAssertFalse(largeAvatar.timing.isAnimated)
        return [smallAvatar, largeAvatar.firstFrame]
    }

    private func assertOriginal(_ image: UIImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(image.renderingMode, .alwaysOriginal, file: file, line: line)
        XCTAssertEqual(image.scale, 1, file: file, line: line)
        XCTAssertEqual(image.imageOrientation, .up, file: file, line: line)
    }

    private func assertBytes(_ actual: [UInt8], equalTo expected: [UInt8], tolerance: Int = 2,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual.count == expected.count else { return }
        for index in actual.indices {
            XCTAssertLessThanOrEqual(abs(Int(actual[index]) - Int(expected[index])), tolerance,
                                     "RGBA byte \(index): \(actual[index]) instead of \(expected[index])", file: file, line: line)
        }
    }
}

private enum AvatarColorFixtures {
    static func bitmap(_ samples: [UInt8], space: CGColorSpace) throws -> CGImage {
        precondition(!samples.isEmpty && samples.count.isMultiple(of: 4))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(samples) as CFData))
        return try XCTUnwrap(CGImage(width: samples.count / 4, height: 1, bitsPerComponent: 8,
                                     bitsPerPixel: 32, bytesPerRow: samples.count, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue
                                         | CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false,
                                     intent: .relativeColorimetric))
    }

    static func png(_ bitmap: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData,
                                                                         UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.encodingFailed }
        return data as Data
    }

    static func encodedBitmap(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func rgba(_ image: CGImage, space: CGColorSpace, background: CGFloat? = nil) throws -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                                 bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                                     | CGImageAlphaInfo.premultipliedLast.rawValue))
            let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
            context.interpolationQuality = .none
            context.setRenderingIntent(.relativeColorimetric)
            if let background {
                let color = try XCTUnwrap(CGColor(colorSpace: space, components: [background, background, background, 1]))
                context.setFillColor(color)
                context.fill(rect)
            }
            context.draw(image, in: rect)
        }
        return bytes
    }

    private enum FixtureError: Error { case encodingFailed }
}
