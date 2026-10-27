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

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .light: return "Слабо"
            case .medium: return "Средне"
            case .strong: return "Сильно"
            }
        }

        var scale: Float {
            switch self {
            case .light: return 0.55
            case .medium: return 1.0
            case .strong: return 1.6
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

    static func apply(to image: CIImage, strength: Strength = .medium) -> CIImage {
        guard let kernel else { return image }
        let scale = strength.scale

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
                min(sharpeningStrength * scale, 1.0)
            ]
        )
        return output?.cropped(to: image.extent) ?? image
    }
}
