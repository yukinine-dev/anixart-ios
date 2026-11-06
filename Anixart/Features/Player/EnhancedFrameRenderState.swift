import CoreGraphics

/// Submission bookkeeping only: no AVPlayer, Metal allocation or shader work.
/// A new frame stays pending until it is submitted, including across a tick
/// where no drawable is available. Configuration changes can reuse a paused
/// frame without continuously processing it.
struct EnhancedFrameRenderState {
    struct Configuration: Equatable {
        let drawableSize: CGSize
        let isFilling: Bool
        let strength: VideoEnhanceFilter.Strength

        var hasDrawableArea: Bool {
            drawableSize.width.isFinite && drawableSize.height.isFinite
                && drawableSize.width > 0 && drawableSize.height > 0
        }
    }

    private var hasFrame = false
    private var hasPendingFrame = false
    private var submittedConfiguration: Configuration?

    mutating func receivedFrame() {
        hasFrame = true
        hasPendingFrame = true
    }

    func needsRender(configuration: Configuration) -> Bool {
        hasFrame && configuration.hasDrawableArea
            && (hasPendingFrame || submittedConfiguration != configuration)
    }

    mutating func didSubmit(configuration: Configuration) {
        guard hasFrame, configuration.hasDrawableArea else { return }
        hasPendingFrame = false
        submittedConfiguration = configuration
    }

    /// Presentation can be lost on activation or a drawable resize, even if
    /// playback is paused and the numeric configuration has not changed.
    mutating func invalidatePresentation() {
        submittedConfiguration = nil
    }

    /// An old item's cached frame must not satisfy a new item's first draw.
    mutating func reset() {
        self = Self()
    }
}
