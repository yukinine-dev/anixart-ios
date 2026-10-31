import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

@MainActor
enum ProfileThemeTestImages {
    static func bitmap(size: CGSize = CGSize(width: 4, height: 6)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let halfWidth = size.width / 2, halfHeight = size.height / 2
            let quadrants: [(UIColor, CGRect)] = [
                (.red, CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight)),
                (.green, CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)),
                (.blue, CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)),
                (.yellow, CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight))
            ]
            for (color, rect) in quadrants { color.setFill(); context.fill(rect) }
        }
    }

    static func png() throws -> Data { try XCTUnwrap(bitmap().pngData()) }

    static func gif(frameCount: Int = 16, size: CGSize = CGSize(width: 16, height: 8),
                    delays: [TimeInterval] = [0.03]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.gif.identifier as CFString, frameCount, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        for index in 0..<frameCount {
            let image = renderer.image { context in
                UIColor(red: CGFloat((index % 3) + 1) / 3, green: CGFloat((index % 5) + 1) / 5,
                        blue: CGFloat((index % 7) + 1) / 7, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let delay = delays[index % delays.count]
            let properties: [CFString: Any] = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay
            ]]
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.encodingFailed }
        return data as Data
    }

    static func jpeg(orientation: Int) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: orientation],
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]
        CGImageDestinationAddImage(destination, try XCTUnwrap(bitmap(size: CGSize(width: 8, height: 4)).cgImage), properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.encodingFailed }
        return data as Data
    }

    /// 4 x 4 indexed GIF with five partial frames. Disposal 1 retains the green
    /// top-left patch, disposal 2 clears the blue top-right patch, and disposal 3
    /// restores the red pixels covered by a temporary yellow bottom-right patch.
    /// The last frame is transparent. No platform image writer can optimize away
    /// the offsets, transparency or disposal modes being tested.
    static let compositingGIF = Data(base64Encoded:
        "R0lGODlhBAAEAPIAAAAAAP8AAAD/AAAA////AP///wAAAAAAACH5BAUKAAAALAAAAAAEAAQAAAMRGBgYGBgYGBgYGBgYGBgYGAkAIfkEBQIAAAAsAAAAAAIAAgAAAwUoKCgoCQAh+QQJHgAAACwCAAAAAgACAAADBTg4ODgJACH5BA0oAAAALAIAAgACAAIAAAMFSEhISAkAIfkEBTIAAAAsAAAAAAQABAAAAxEICAgICAgICAgICAgICAgICQA7")!

    private enum FixtureError: Error { case encodingFailed }
}

struct ProfileThemeTestPixels {
    struct Pixel {
        let red: Int, green: Int, blue: Int, alpha: Int
    }
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init(_ image: UIImage) throws {
        let image = try XCTUnwrap(image.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                                                 bitsPerComponent: 8, bytesPerRow: width * 4,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                 bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> Pixel {
        precondition((0..<width).contains(x) && (0..<height).contains(y))
        let offset = (y * width + x) * 4
        return Pixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]), alpha: Int(bytes[offset + 3]))
    }

    var opaquePixels: [Pixel] {
        (0..<height).flatMap { y in (0..<width).map { x in pixel(x: x, y: y) } }.filter { $0.alpha > 240 }
    }
}

func assertProfileThemePixel(_ pixels: ProfileThemeTestPixels, x: Int, y: Int, red: Int, green: Int, blue: Int,
                             file: StaticString = #filePath, line: UInt = #line) {
    let pixel = pixels.pixel(x: x, y: y)
    XCTAssertEqual(Double(pixel.red), Double(red), accuracy: 15, file: file, line: line)
    XCTAssertEqual(Double(pixel.green), Double(green), accuracy: 15, file: file, line: line)
    XCTAssertEqual(Double(pixel.blue), Double(blue), accuracy: 15, file: file, line: line)
    XCTAssertGreaterThan(pixel.alpha, 240, file: file, line: line)
}

actor ProfileThemeTestDataSource {
    private var response: Data?
    private let gate: ProfileTestGate?
    private(set) var requests: [URL] = []

    init(data: Data?, gate: ProfileTestGate? = nil) { response = data; self.gate = gate }
    func setResponse(_ data: Data?) { response = data }

    func fetch(_ url: URL) async -> Data? {
        requests.append(url)
        if let gate { await gate.wait() }
        return response
    }
}
