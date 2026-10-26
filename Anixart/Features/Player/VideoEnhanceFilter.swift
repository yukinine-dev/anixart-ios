import AVFoundation
import CoreImage
import Foundation
import os

/// "Режим улучшения видео +".
///
/// The Android build runs the Anime4K-derived shader as an ExoPlayer GL effect;
/// here the same kernel runs as a Core Image filter inside the player item's
/// video composition. The coefficients are the ones the APK sets.
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

    /// Video composition that runs the kernel over every frame of `asset`.
    ///
    /// HLS and other streamed-but-not-file assets have no composable tracks, so
    /// this returns nil for them and the caller leaves the picture untouched.
    static func videoComposition(for asset: AVAsset) async -> AVVideoComposition? {
        guard isAvailable else { return nil }
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), !tracks.isEmpty else {
            log.notice("asset has no video tracks to compose; enhancement stays off")
            return nil
        }

        return try? await AVVideoComposition.videoComposition(with: asset) { request in
            request.finish(with: apply(to: request.sourceImage), context: nil)
        }
    }
}
