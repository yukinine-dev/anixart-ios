import CoreImage
import Foundation
import os

/// Runs a converted Anime4K chain over one frame.
///
/// The hand-written kernel next door measures an edge and sharpens it. These are
/// trained convolutions: `restore` is four 3x3 layers with a residual connection
/// that was fitted to undo the blur and compression a low-bitrate encode leaves,
/// and `upscaleX2` is four more plus a depth-to-space layer that doubles the
/// picture. That is a different kind of thing from a sharpener, and it is why
/// faces come back rather than just getting crisper edges.
///
/// The passes and their wiring are generated from the upstream shaders -- see
/// `Anime4KChain.swift` and `Tools/convert-anime4k.py`. Nothing here knows what
/// any pass does; it only knows how to feed one.
enum Anime4KFilter {
    private static let log = Logger(subsystem: "app.anixart.client", category: "player")

    private static let library: Data? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            log.notice("no default.metallib in the bundle; Anime4K is unavailable")
            return nil
        }
        return try? Data(contentsOf: url)
    }()

    /// One `CIKernel` per generated function, built once.
    ///
    /// Nine kernels across the two chains, and `CIKernel(functionName:)` parses
    /// the library each time it is called -- doing that sixty times a second
    /// would cost more than the convolutions.
    private static let kernels: [String: CIKernel] = {
        guard let library else { return [:] }
        var built: [String: CIKernel] = [:]
        for pass in Anime4KChain.restore + Anime4KChain.upscaleX2 {
            guard built[pass.function] == nil else { continue }
            do {
                built[pass.function] = try CIKernel(
                    functionName: pass.function,
                    fromMetalLibraryData: library
                )
            } catch {
                log.error(
                    "Anime4K kernel \(pass.function, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                return [:]
            }
        }
        return built
    }()

    static var isAvailable: Bool { !kernels.isEmpty }

    /// Undoes what the encode did, at the frame's own resolution.
    static func restore(_ image: CIImage) -> CIImage? {
        run(Anime4KChain.restore, on: image)
    }

    /// Doubles the picture.
    ///
    /// Worth it only when the display is actually asking for more pixels than
    /// the frame has; the caller decides, as mpv does with its `WHEN` directive.
    static func upscaleX2(_ image: CIImage) -> CIImage? {
        run(Anime4KChain.upscaleX2, on: image)
    }

    private static func run(_ chain: [Anime4KPass], on image: CIImage) -> CIImage? {
        guard isAvailable else { return nil }

        // Every pass computes its own sampling position from `dest.coord()` and
        // the sizes it is handed, and that arithmetic assumes an image whose
        // extent starts at the origin. A frame off the player does, but say so
        // rather than rely on it.
        let start = image.extent
        guard start.width > 0, start.height > 0 else { return nil }
        var images: [String: CIImage] = [
            "MAIN": image.transformed(by: CGAffineTransform(
                translationX: -start.origin.x,
                y: -start.origin.y
            ))
        ]

        for pass in chain {
            guard let kernel = kernels[pass.function],
                  let sized = images[pass.sizedLike]
            else { return nil }

            let width = (sized.extent.width * pass.scale).rounded()
            let height = (sized.extent.height * pass.scale).rounded()
            let extent = CGRect(x: 0, y: 0, width: width, height: height)

            var arguments: [Any] = []
            var sources: [CGSize] = []
            for name in pass.binds {
                guard let bound = images[name] else { return nil }
                // The convolutions read a one-pixel ring, so the edge rows have
                // to sample something.
                arguments.append(bound.clampedToExtent())
                arguments.append(CIVector(x: bound.extent.width, y: bound.extent.height))
                sources.append(CGSize(width: bound.extent.width, height: bound.extent.height))
            }
            arguments.append(CIVector(x: width, y: height))

            guard let output = kernel.apply(
                extent: extent,
                roiCallback: { index, rect in
                    // The region of interest is in the *source's* pixels, which
                    // are not the destination's when a pass doubles the picture.
                    let source = sources[Int(index)]
                    let scaleX = source.width / width
                    let scaleY = source.height / height
                    return rect
                        .applying(CGAffineTransform(scaleX: scaleX, y: scaleY))
                        .insetBy(dx: -2, dy: -2)
                },
                arguments: arguments
            ) else { return nil }

            images[pass.save] = output.cropped(to: extent)
        }

        return images["MAIN"]
    }
}
