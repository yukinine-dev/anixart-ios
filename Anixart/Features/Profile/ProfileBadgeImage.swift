import SwiftUI
import UIKit
import Lottie
import AnixartKit

@MainActor
struct ProfileBadgeImage: View {
    let badge: Badge
    var size: CGFloat = 88
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @State private var isVisible = false

    var body: some View {
        Group {
            if badge.isAnimated, let url = badge.artworkURL {
                ProfileAnimatedBadgeImage(url: url, isAnimating: ProfileBadgePlayback.allowsAnimation(
                    isVisible: isVisible, isActive: scenePhase == .active,
                    reduceMotion: reduceMotion, resourceSaving: resourceSaving))
            } else {
                CachedAsyncImage(url: badge.artworkURL, maxPixelSize: size) {
                    $0.resizable().scaledToFit()
                } placeholder: { ProfileBadgeImagePlaceholder() }
            }
        }
        .frame(width: size, height: size)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ProfileBadgeImageVisibility.self,
                                       value: geometry.frame(in: .global).intersects(UIScreen.main.bounds))
            }
        }
        .onPreferenceChange(ProfileBadgeImageVisibility.self) { isVisible = $0 }
        .onDisappear { isVisible = false }
        .accessibilityLabel(badge.name ?? "Значок")
    }
}

private struct ProfileBadgeImageVisibility: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct ProfileBadgeImagePlaceholder: View {
    var body: some View {
        Image(systemName: "seal").resizable().scaledToFit().foregroundStyle(.tertiary).padding(12)
    }
}

@MainActor
private struct ProfileAnimatedBadgeImage: View {
    let url: URL
    let isAnimating: Bool
    @State private var animation: LottieAnimation?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let animation, loadedURL == url {
                ProfileBadgeLottieView(animation: animation, isAnimating: isAnimating)
            } else {
                ProfileBadgeImagePlaceholder()
            }
        }
        .task(id: url) {
            animation = nil
            loadedURL = nil
            let loaded = await ProfileBadgeAnimationLoader.shared.animation(for: url)
            guard !Task.isCancelled else { return }
            animation = loaded
            loadedURL = url
        }
    }
}

/// Keep the authored JSON timeline. Visibility/power preferences only pause it;
/// unrelated SwiftUI updates must not recreate the layer or restart its clock.
@MainActor
enum ProfileBadgePlayback {
    static func allowsAnimation(isVisible: Bool, isActive: Bool, reduceMotion: Bool, resourceSaving: Bool) -> Bool {
        isVisible && isActive && !reduceMotion && !resourceSaving
    }

    static func update(_ view: LottieAnimationView, animation: LottieAnimation, isAnimating: Bool) {
        if view.animation !== animation {
            view.animation = animation
            view.currentProgress = 0
        }
        if isAnimating {
            if !view.isAnimationPlaying && !view.isAnimationQueued { view.play() }
        } else {
            view.pause()
        }
    }
}

@MainActor
struct ProfileBadgeLottieView: UIViewRepresentable {
    let animation: LottieAnimation
    let isAnimating: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(animation: nil)
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pause
        view.loopMode = .loop
        view.respectAnimationFrameRate = true
        view.animateLayoutChangesWithCurrentCoreAnimationContext = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        ProfileBadgePlayback.update(view, animation: animation, isAnimating: isAnimating)
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        ProfileBadgePlayback.update(view, animation: animation, isAnimating: isAnimating)
    }

    static func dismantleUIView(_ view: LottieAnimationView, coordinator: ()) {
        view.pause()
        view.animation = nil
    }
}
