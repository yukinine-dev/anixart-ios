import SwiftUI
import UIKit
import AnixartKit

@MainActor
struct ProfileShowcaseBackground: View {
    let theme: ProfileTheme?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @State private var isVisible = false
    @State private var hasAppeared = false

    private var animationState: ProfileThemeAnimationState {
        ProfileThemeAnimationState(isVisible: hasAppeared && isVisible, isSceneActive: scenePhase == .active,
                                    reduceMotion: reduceMotion || resourceSaving, particleMotionEnabled: theme?.themeAnimationEnabled == true)
    }

    var body: some View {
        GeometryReader { geometry in
            if let theme, theme.themeEnabled != false {
                ZStack {
                    if let url = AnixartURL.image(theme.themeBackgroundUrl) {
                        ProfileThemeBitmap(url: url, mode: ProfileThemeLayout.BackgroundMode(theme.themeBackgroundMode),
                                           displayScale: displayScale, isAnimating: animationState.texturesRunning)
                            .opacity(ProfileThemeLayout.alpha(theme.themeBackgroundAlpha, fallback: 1))
                    }
                    // Android draws the gradient over the bitmap, not underneath it.
                    gradient(theme, size: geometry.size)
                    icons(theme, size: geometry.size)
                }
                .id(theme)
                .preference(key: ProfileShowcaseVisibility.self,
                            value: geometry.frame(in: .global).intersects(UIScreen.main.bounds))
            }
        }
        .onPreferenceChange(ProfileShowcaseVisibility.self) { isVisible = $0 }
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func gradient(_ theme: ProfileTheme, size: CGSize) -> some View {
        let start = ProfileThemeColor.color(theme.themeGradientStartColor) ?? .clear
        let end = ProfileThemeColor.color(theme.themeGradientEndColor) ?? .clear
        let direction = ProfileThemeLayout.GradientDirection(theme.themeGradientAngle)
        if direction == .radial {
            RadialGradient(colors: [start, end], center: .center, startRadius: 0,
                           endRadius: max(1, ProfileThemeLayout.radialRadius(for: size)))
        } else {
            LinearGradient(colors: [start, end], startPoint: direction.endpoints.start, endPoint: direction.endpoints.end)
        }
    }

    @ViewBuilder
    private func icons(_ theme: ProfileTheme, size: CGSize) -> some View {
        let running = animationState.particlesRunning
        let layout = ProfileThemeLayout(theme: theme)
        if let asset = ProfileThemeArtwork.name(for: theme.themeIconResName) {
            ProfileThemeIcons(image: Image(asset), layout: layout, size: size,
                              displayScale: displayScale, isRunning: running)
        } else if let url = AnixartURL.image(theme.themeIconUrl) {
            ProfileThemeTexture(url: url, pixelSize: 256, isAnimating: animationState.texturesRunning) { image, _ in
                ProfileThemeIcons(image: Image(uiImage: image), layout: layout, size: size,
                                  displayScale: displayScale, isRunning: running)
            } placeholder: { Color.clear }
        }
    }
}

private struct ProfileShowcaseVisibility: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// A single cached texture, reused by the canvas even in tile mode.
@MainActor
private struct ProfileThemeBitmap: View {
    let url: URL
    let mode: ProfileThemeLayout.BackgroundMode
    let displayScale: CGFloat
    let isAnimating: Bool

    var body: some View {
        ProfileThemeTexture(url: url, pixelSize: 1200, isAnimating: isAnimating) { bitmap, sourceSize in
            ProfileThemeBitmapDrawing(bitmap: bitmap, sourceSize: sourceSize, mode: mode, displayScale: displayScale)
        } placeholder: { Color.clear }
    }
}

/// Kept separate from loading so native tile orientation can be rendered and
/// checked with an asymmetric bitmap, without networking or animation clocks.
@MainActor
struct ProfileThemeBitmapDrawing: View {
    let bitmap: UIImage
    let sourceSize: CGSize
    let mode: ProfileThemeLayout.BackgroundMode
    let displayScale: CGFloat

    var body: some View {
        Canvas { context, size in
            let image = Image(uiImage: bitmap)
            if mode == .tile {
                let scale = ProfileThemeLayout.tileScale(sourceSize: sourceSize, decodedSize: bitmap.size, displayScale: displayScale)
                // Native tiled shading is one draw, even for a 1 px texture.
                // Its origin is the tile's bottom-left corner in user space.
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .tiledImage(image, origin: CGPoint(x: 0, y: bitmap.size.height * scale), scale: scale))
            } else {
                context.draw(image, in: ProfileThemeLayout.backgroundRect(imageSize: bitmap.size, container: size, mode: mode))
            }
        }
    }
}

@MainActor
private struct ProfileThemeIcons: View {
    let image: Image
    let layout: ProfileThemeLayout
    let size: CGSize
    let displayScale: CGFloat
    let isRunning: Bool
    @State private var clock = ProfileThemeMotionClock()

    var body: some View {
        let particles = layout.particles(in: size, displayScale: displayScale)
        let tint = ProfileThemeColor.color(layout.theme.themeIconColor)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRunning)) { timeline in
            Canvas { context, container in
                let resolved = ProfileThemeArtwork.resolve(image, in: context)
                let elapsed = clock.elapsed(at: timeline.date)
                for particle in particles {
                    var layer = context
                    let position = particle.position(at: elapsed, in: container)
                    layer.translateBy(x: position.x, y: position.y)
                    layer.rotate(by: .degrees(particle.rotation + elapsed * particle.rotationSpeed))
                    layer.opacity = particle.opacity
                    ProfileThemeArtwork.draw(resolved, in: CGRect(x: 0, y: 0, width: particle.size, height: particle.size),
                                             context: layer, tint: tint)
                }
            }
        }
        .onAppear { clock.setRunning(isRunning, at: Date()) }
        .onChange(of: isRunning, initial: true) { _, running in clock.setRunning(running, at: Date()) }
        .onDisappear { clock.setRunning(false, at: Date()) }
    }
}

/// Exact vector paths from the APK's named resources. Remote theme icons retain
/// their own artwork; unknown local resources are not guessed by substring.
enum ProfileThemeArtwork {
    static func resolve(_ image: Image, in context: GraphicsContext) -> GraphicsContext.ResolvedImage {
        context.resolve(image.renderingMode(.original))
    }

    /// Vector assets can ignore ResolvedImage.shading. Fill their rendered alpha
    /// mask instead, keeping the same transform and the bitmap's source alpha.
    static func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, context: GraphicsContext, tint: Color?) {
        guard let tint else { context.draw(image, in: rect); return }
        var tinted = context
        let opacity = tinted.opacity
        // Particle opacity belongs to the final fill, not to both mask and fill.
        tinted.opacity = 1
        tinted.clipToLayer { mask in
            mask.opacity = 1
            mask.draw(image, in: rect)
        }
        tinted.opacity = opacity
        tinted.fill(Path(rect), with: .color(tint))
    }

    static func name(for resource: String?) -> String? {
        guard let resource else { return nil }
        return ["ic_heart": "ProfileThemeHeart", "ic_heart_outline": "ProfileThemeHeartOutline", "ic_star_rate": "ProfileThemeStar",
                "ic_stars": "ProfileThemeStars", "ic_crown": "ProfileThemeCrown", "ic_bookmarks": "ProfileThemeBookmark",
                "ic_bookmarks_filled": "ProfileThemeBookmarkFilled"][resource]
    }
}
