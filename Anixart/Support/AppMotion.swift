import SwiftUI

/// Motion is a short orientation/continuity cue, never a prerequisite for input.
/// Themes, text input and keyboard activation do not opt into these animations.
struct AppMotionPolicy: Equatable {
    let reduceMotion: Bool
    let resourceSaving: Bool
    var isEnabled: Bool { !reduceMotion && !resourceSaving }
    var duration: Double { isEnabled ? 0.22 : 0 }
    var animation: Animation? {
        isEnabled ? .timingCurve(0.25, 1, 0.5, 1, duration: duration) : nil
    }

    /// A caller can retain its existing animation while sharing the same input,
    /// accessibility and resource-saving gates as the selection controls.
    func resolvedAnimation(_ preferred: Animation? = nil, animated: Bool = true) -> Animation? {
        guard isEnabled, animated else { return nil }
        return preferred ?? animation
    }

    @MainActor
    func perform(animated: Bool = true, using preferred: Animation? = nil, _ updates: () -> Void) {
        if let animation = resolvedAnimation(preferred, animated: animated) { withAnimation(animation, updates) }
        else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, updates)
        }
    }
}

/// Tracks the user's intended target, not a second copy of the selected value.
/// Async selectors can publish an older/default target before the chosen one;
/// those changes must not consume or animate a newer touch/keyboard intent.
struct SelectionMotionIntent<Selection: Equatable> {
    private var target: Selection?
    private var isAnimated = false

    init() { }

    var hasPendingSelection: Bool { target != nil }

    func isPending(_ selection: Selection) -> Bool { target == selection }

    mutating func register(_ selection: Selection, fromKeyboard: Bool = false) {
        target = selection
        isAnimated = !fromKeyboard
    }

    func shouldAnimate(_ selection: Selection?) -> Bool {
        guard let selection else { return false }
        return isAnimated && target == selection
    }

    func animation(for selection: Selection?, policy: AppMotionPolicy) -> Animation? {
        shouldAnimate(selection) ? policy.animation : nil
    }

    mutating func complete(_ selection: Selection?) {
        guard let selection, target == selection else { return }
        reset()
    }

    mutating func reset() {
        target = nil
        isAnimated = false
    }
}
