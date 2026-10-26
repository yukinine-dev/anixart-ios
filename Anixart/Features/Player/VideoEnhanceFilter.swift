import AVFoundation
import CoreImage
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

    static func apply(to image: CIImage) -> CIImage {
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
                edgeThreshold,
                deblurIntensity,
                sharpeningStrength
            ]
        )
        return output?.cropped(to: image.extent) ?? image
    }
}
