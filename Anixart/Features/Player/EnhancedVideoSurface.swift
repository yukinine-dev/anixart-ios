import AVFoundation
import CoreGraphics
import CoreImage
import MetalKit
import SwiftUI
import os

/// Draws the player's frames through the enhancement kernel.
///
/// The first attempt ran the kernel as an `AVVideoComposition`, which only works
/// on an asset with composable tracks. An HLS stream has none -- and HLS is
/// everything the built-in player gets, since the video comes from a hosting's
/// own API -- so the toggle turned itself straight back off. Tapping the item
/// with `AVPlayerItemVideoOutput` and drawing the frames here works on anything
/// the player can decode.
///
/// This sits over the `AVPlayerLayer` rather than replacing it: the layer keeps
/// decoding, keeps the audio and keeps picture in picture working.
struct EnhancedVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var isFilling: Bool
    /// Called when the kernel cannot be run at all, so the toggle is not left
    /// on over a black screen.
    var onFailure: (String) -> Void

    func makeCoordinator() -> Renderer {
        Renderer(player: player, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.delegate = context.coordinator
        // Core Image renders into the drawable's texture, which it cannot do
        // when the drawable is framebuffer-only.
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        // Transparent, so until the first enhanced frame arrives -- right after
        // a quality switch, say -- the player layer shows through instead of a
        // black flash. In fit mode the letterbox bars reveal the layer's own
        // black.
        view.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        context.coordinator.isFilling = isFilling
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.isFilling = isFilling
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
        coordinator.detach()
    }

    /// Pulls each frame off the player, runs the kernel and presents it.
    final class Renderer: NSObject, MTKViewDelegate {
        private static let log = Logger(subsystem: "app.anixart.client", category: "player")

        let device: MTLDevice?
        var isFilling = false

        private let player: AVPlayer
        private let onFailure: (String) -> Void
        private let queue: MTLCommandQueue?
        private let context: CIContext?
        private let output: AVPlayerItemVideoOutput
        private weak var attachedItem: AVPlayerItem?
        /// A quality change replaces the item, and SwiftUI has no reason to
        /// refresh this view when it does -- so the output has to notice for
        /// itself, or it keeps pulling from an item the player has let go and
        /// the picture freezes.
        private var itemObservation: NSKeyValueObservation?
        /// Kept so a paused picture still redraws; `hasNewPixelBuffer` is false
        /// while nothing is advancing, and without this the screen goes black
        /// the moment the user pauses.
        private var lastBuffer: CVPixelBuffer?
        private var hasReportedFailure = false

        init(player: AVPlayer, onFailure: @escaping (String) -> Void) {
            self.player = player
            self.onFailure = onFailure
            self.device = MTLCreateSystemDefaultDevice()
            self.queue = device?.makeCommandQueue()
            // The kernel's coefficients and thresholds come from a GLSL effect
            // that ran on gamma-encoded video texels. Core Image's default
            // working space is linear, where 0.05 and 0.95 mean something else
            // entirely and the sharpening overshoots -- so it is pinned to
            // sRGB, which is also cheaper.
            let working = CGColorSpace(name: CGColorSpace.sRGB)
            self.context = queue.map {
                CIContext(mtlCommandQueue: $0, options: [
                    .workingColorSpace: working as Any,
                    .cacheIntermediates: false
                ])
            }
            self.output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            super.init()
            itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                self?.attachToCurrentItem()
            }
        }

        deinit {
            itemObservation = nil
            attachedItem?.remove(output)
        }

        /// The item is replaced when the user changes quality, so the output has
        /// to follow it.
        func attachToCurrentItem() {
            guard let item = player.currentItem, item !== attachedItem else { return }
            attachedItem?.remove(output)
            item.add(output)
            attachedItem = item
            lastBuffer = nil
        }

        func detach() {
            itemObservation = nil
            attachedItem?.remove(output)
            attachedItem = nil
            lastBuffer = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let queue, let context else {
                report("Metal недоступен на этом устройстве")
                return
            }
            guard VideoEnhanceFilter.isAvailable else {
                report("Шейдер улучшения не собран в этой сборке")
                return
            }

            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time),
               let fresh = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                lastBuffer = fresh
            } else if lastBuffer == nil,
                      let first = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                // Turned on while paused: there is no *new* frame, but there is
                // a current one, and without this the picture would go black.
                lastBuffer = first
            }
            guard let buffer = lastBuffer,
                  let drawable = view.currentDrawable,
                  let commandBuffer = queue.makeCommandBuffer()
            else { return }

            let source = CIImage(cvPixelBuffer: buffer)
            let enhanced = VideoEnhanceFilter.apply(to: source)
            let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
            let placed = Self.place(enhanced, in: size, filling: isFilling)

            let destination = CIRenderDestination(
                width: drawable.texture.width,
                height: drawable.texture.height,
                pixelFormat: view.colorPixelFormat,
                commandBuffer: commandBuffer,
                mtlTextureProvider: { drawable.texture }
            )
            // Core Image's origin is bottom-left and the drawable's is top-left.
            destination.isFlipped = true

            do {
                _ = try context.startTask(toClear: destination)
                _ = try context.startTask(toRender: placed, to: destination)
            } catch {
                report("Кадр не удалось обработать: \(error.localizedDescription)")
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }

        /// Same geometry as `AVLayerVideoGravity`: fit by default, fill when the
        /// user has tapped the fill button.
        private static func place(_ image: CIImage, in size: CGSize, filling: Bool) -> CIImage {
            let extent = image.extent
            guard extent.width > 0, extent.height > 0, size.width > 0, size.height > 0 else { return image }

            let scaleX = size.width / extent.width
            let scaleY = size.height / extent.height
            let scale = filling ? max(scaleX, scaleY) : min(scaleX, scaleY)

            let width = extent.width * scale
            let height = extent.height * scale
            return image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(
                    translationX: (size.width - width) / 2 - extent.origin.x * scale,
                    y: (size.height - height) / 2 - extent.origin.y * scale
                ))
        }

        /// One message per player, since `draw` runs sixty times a second.
        private func report(_ message: String) {
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            Self.log.notice("enhancement unavailable: \(message, privacy: .public)")
            let onFailure = self.onFailure
            Task { @MainActor in onFailure(message) }
        }
    }
}
