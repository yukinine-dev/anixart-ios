import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// "Режим улучшения видео +".
///
/// The Android build runs the Anime4K-derived shader as an ExoPlayer GL effect;
/// here the same kernel runs as a Core Image filter over the frames
/// `EnhancedVideoSurface` pulls off the player. A video composition would have
/// been tidier, but it cannot touch an HLS stream, and HLS is all the built-in
/// player gets. The coefficients are the ones the APK sets.
///
/// The kernel lives in `VideoEnhance.ci.metal` and is compiled into the target's
/// default Metal library. If that library is missing -- an older toolchain, a
/// build without the `-fcikernel` flags -- `isAvailable` is false and the player
/// hides the option rather than offering a toggle that does nothing.
struct VideoEnhanceFilter {
    private static let log = Logger(subsystem: "app.anixart.client", category: "player")

    /// Defaults taken verbatim from AnixAnime4KShaderProgram.
    static let refineStrength: Float = 1.0
    static let refineBias: Float = 0.0
    static let edgeThreshold: Float = 0.1
    static let deblurIntensity: Float = 0.8
    static let sharpeningStrength: Float = 0.3

    /// How hard to push it.
    ///
    /// The APK has one setting and no dial. A dial is the honest answer to "it
    /// could be better and I don't know how": `medium` is the APK's own numbers,
    /// and the other two scale the two strengths that decide how much new
    /// contrast is invented. The edge detector and the anti-ringing clamp are
    /// left alone, because those are what keep it from breaking.
    enum Strength: Int, CaseIterable, Identifiable, Sendable {
        case light = 0
        case medium = 1
        case strong = 2
        /// The real Anime4K: trained convolutions rather than a sharpener.
        ///
        /// The three above are the hand-written kernel at three amounts. This
        /// one is a different algorithm altogether, so it does not belong on the
        /// same axis -- but it belongs in the same menu, because it answers the
        /// same question and the user should be able to put the two side by side
        /// on one episode.
        case neural = 3

        var id: Int { rawValue }

        /// Offered only when its kernels actually loaded.
        static var available: [Strength] {
            allCases.filter { $0 != .neural || Anime4KFilter.isAvailable }
        }

        var title: String {
            switch self {
            case .light: return "Слабо"
            case .medium: return "Средне"
            case .strong: return "Сильно"
            case .neural: return "Anime4K"
            }
        }

        var usesNeuralChain: Bool { self == .neural }

        var scale: Float {
            switch self {
            case .light: return 0.55
            case .medium: return 1.0
            case .strong: return 1.6
            case .neural: return 1.0
            }
        }
    }

    private static let kernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
            log.notice("no default.metallib in the bundle; video enhancement is unavailable")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try CIKernel(functionName: "anixVideoEnhance", fromMetalLibraryData: data)
        } catch {
            log.error("video enhancement kernel failed to load: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    static var isAvailable: Bool { kernel != nil }

    /// The restore pass, run twice.
    ///
    /// Two weak passes beat one strong one, and not by a little. The kernel
    /// pulls each edge pixel toward the darker side of its gradient; a large
    /// step overshoots on anything that is not a clean straight edge, which is
    /// most of a face -- the corner of an eye, the curve of a jaw. Two small
    /// steps converge on the same line, and the second one is working on a
    /// picture whose gradients the first already cleaned up, so it aims better.
    /// The same reason every iterative sharpener does it this way.
    ///
    /// Debanding runs in the first pass only: once is enough to flatten a
    /// terrace, and doing it twice would start eating real shading.
    static func apply(to image: CIImage, strength: Strength = .medium) -> CIImage {
        if strength.usesNeuralChain {
            // No fallback dressed up as success: if the chain cannot run, the
            // frame goes through untouched and the picture is simply the
            // decoder's, which is honest and visible.
            return Anime4KFilter.restore(image) ?? image
        }
        let step = strength.scale * 0.6
        let first = run(image, scale: step, deband: 1.0)
        return run(first, scale: step, deband: 0.0)
    }

    /// The same kernel again, after the frame has been stretched to the screen.
    ///
    /// Anime4K's own chain is restore, upscale, restore, and on a phone the
    /// second restore is the one that shows. A 720p frame across a landscape
    /// iPhone is close to a 2x upscale: whatever the first pass put back at the
    /// decoded grid is resampled soft again on the way to the display, and a
    /// one-pixel kernel can only put an edge back on the grid it is run at.
    ///
    /// It pushes less hard than the first pass -- 60% -- because it is working
    /// on interpolated pixels, where there is no detail to recover, only an edge
    /// to keep.
    static func applyAfterUpscale(to image: CIImage, strength: Strength) -> CIImage {
        // The neural chain does its own upscaling, with a layer trained for it.
        if strength.usesNeuralChain { return image }
        // No debanding here: the pixels are interpolated, so a terrace has
        // already been smeared into a ramp and there is nothing left to flatten
        // -- only real detail to lose.
        return run(image, scale: strength.scale * 0.5, deband: 0.0)
    }

    /// Lanczos rather than the default resample.
    ///
    /// A bilinear stretch to the screen throws away most of what the first pass
    /// recovered, because it averages every output pixel from two inputs. Core
    /// Image has a proper resampler; this is the one place in the chain where
    /// using it costs nothing but a filter call.
    static func scaled(_ image: CIImage, by scale: CGFloat) -> CIImage {
        guard scale.isFinite, scale > 0, abs(scale - 1) > 0.01 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        guard let output = filter.outputImage, !output.extent.isInfinite, !output.extent.isEmpty else {
            return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return output
    }

    private static func run(_ image: CIImage, scale: Float, deband: Float) -> CIImage {
        guard let kernel else { return image }

        // The kernel reads a one-pixel neighbourhood, so the ROI grows by one on
        // each side; clamping first keeps the edge rows from sampling nothing.
        let clamped = image.clampedToExtent()
        let output = kernel.apply(
            extent: image.extent,
            roiCallback: { _, rect in rect.insetBy(dx: -1, dy: -1) },
            arguments: [
                clamped,
                refineStrength,
                refineBias,
                // Left at the APK's value: this is the threshold the detector
                // fires at, not the amount, and moving it changes what counts as
                // an edge rather than how firmly it is treated.
                edgeThreshold,
                min(deblurIntensity * scale, 1.0),
                min(sharpeningStrength * scale, 1.0),
                deband
            ]
        )
        return output?.cropped(to: image.extent) ?? image
    }
}
