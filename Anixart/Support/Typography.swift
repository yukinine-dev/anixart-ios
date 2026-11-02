import SwiftUI
import UIKit

/// The app's typeface and shared text-style metrics.
///
/// Anixart on Android styles nearly every text appearance as `sans-serif-medium`,
/// which is Roboto on stock Android, so the port ships Roboto (Apache-2.0) and
/// routes every `.font(...)` through here. Roboto remains the default; SF Pro uses
/// native system fonts. The sizes are Apple's text-style sizes at the Large content
/// size, and both choices preserve Dynamic Type.
///
/// `Product Sans`, which the APK bundles for a single style, is Google
/// proprietary and is not shipped -- see Anixart/Resources/Fonts/LICENSE.txt.
enum AppFont {
    static let family = "Roboto"
    static let preferenceStorageKey = "appearance.typeface"

    /// Accessing the observable preference from a SwiftUI body (including via
    /// `Font.ax`) registers that body for font changes, not just the root view.
    static var typeface: AppTypeface { AppTypefacePreferences.shared.typeface }

    /// Bundled Roboto names, retained for existing callers and font registration.
    /// Roboto only ships three weights here, so heavier requests round down to Bold.
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "Roboto-Regular"
        case .medium, .semibold: return "Roboto-Medium"
        default: return "Roboto-Bold"
        }
    }

    /// Point size of a text style at the default (Large) content size.
    static func size(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

extension AppFont {
    /// Dynamic Type font for UIKit, using the same base sizes as SwiftUI.
    @MainActor
    static func uiFont(_ style: Font.TextStyle, _ weight: Font.Weight? = nil,
                       typeface: AppTypeface, compatibleWith traits: UITraitCollection? = nil) -> UIFont {
        let base = uiFont(fixed: size(of: style), resolvedWeight(for: style, weight), typeface: typeface)
        return UIFontMetrics(forTextStyle: uiTextStyle(for: style)).scaledFont(for: base, compatibleWith: traits)
    }

    @MainActor
    static func uiFont(fixed size: CGFloat, _ weight: Font.Weight = .regular, typeface: AppTypeface) -> UIFont {
        if typeface == .roboto, let bundled = UIFont(name: name(for: weight), size: size) {
            return bundled
        }
        // Also a safe fallback if a bundled font is unavailable in a preview.
        return .systemFont(ofSize: size, weight: uiWeight(for: weight))
    }

    /// Font-only defaults for newly created bars, then update existing instances:
    /// UIAppearance does not retroactively restyle already visible UIKit views.
    /// Do not read appearance proxies or replace their standardAppearance here;
    /// doing so would lose a theme's backgrounds, shadows, and other attributes.
    @MainActor
    static func applyToUIKitBars() {
        applyToUIKitBars(typeface: typeface)
    }

    @MainActor
    static func applyToUIKitBars(typeface: AppTypeface) {
        UINavigationBar.appearance().titleTextAttributes = [.font: uiFont(.headline, .medium, typeface: typeface)]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: uiFont(.largeTitle, .bold, typeface: typeface)]
        let caption = tabTitleFont(typeface: typeface, compatibleWith: nil)
        for state in [UIControl.State.normal, .selected, .disabled, .focused] {
            UITabBarItem.appearance().setTitleTextAttributes([.font: caption], for: state)
        }

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                applyToUIKitBars(in: window, typeface: typeface)
            }
        }
    }

    /// Copies each live bar's own appearances and changes only its font entries.
    /// The traversal includes presented sheets and all tabs that are already loaded.
    @MainActor
    static func applyToUIKitBars(in view: UIView, typeface: AppTypeface) {
        if let navigation = view as? UINavigationBar {
            apply(typeface, to: navigation)
            return
        }
        if let tab = view as? UITabBar {
            apply(typeface, to: tab)
            return
        }
        for child in view.subviews {
            applyToUIKitBars(in: child, typeface: typeface)
        }
    }

    @MainActor
    static func apply(_ typeface: AppTypeface, to bar: UINavigationBar,
                      compatibleWith traits: UITraitCollection? = nil) {
        let traits = traits ?? bar.traitCollection
        let standard = navigationAppearance(from: bar.standardAppearance, typeface: typeface, compatibleWith: traits)
        let edge = bar.scrollEdgeAppearance.map { navigationAppearance(from: $0, typeface: typeface, compatibleWith: traits) }
        let compact = bar.compactAppearance.map { navigationAppearance(from: $0, typeface: typeface, compatibleWith: traits) }
        let compactEdge = bar.compactScrollEdgeAppearance.map { navigationAppearance(from: $0, typeface: typeface, compatibleWith: traits) }
        bar.standardAppearance = standard
        bar.scrollEdgeAppearance = edge
        bar.compactAppearance = compact
        bar.compactScrollEdgeAppearance = compactEdge
        bar.setNeedsLayout()
    }

    @MainActor
    static func apply(_ typeface: AppTypeface, to bar: UITabBar,
                      compatibleWith traits: UITraitCollection? = nil) {
        let traits = traits ?? bar.traitCollection
        bar.standardAppearance = tabAppearance(from: bar.standardAppearance, typeface: typeface, compatibleWith: traits)
        bar.scrollEdgeAppearance = bar.scrollEdgeAppearance.map { tabAppearance(from: $0, typeface: typeface, compatibleWith: traits) }
        let font = tabTitleFont(typeface: typeface, compatibleWith: traits)
        for item in bar.items ?? [] {
            for state in [UIControl.State.normal, .selected, .disabled, .focused] {
                var attributes = item.titleTextAttributes(for: state) ?? [:]
                attributes[.font] = font
                item.setTitleTextAttributes(attributes, for: state)
            }
        }
        bar.setNeedsLayout()
    }

    /// A font-only copy of a live appearance or a theme-owned template. Theme code
    /// can use this before assigning proxy defaults, without reading proxy getters.
    @MainActor
    static func navigationAppearance(from original: UINavigationBarAppearance, typeface: AppTypeface,
                                     compatibleWith traits: UITraitCollection? = nil) -> UINavigationBarAppearance {
        let appearance = original.copy() as! UINavigationBarAppearance
        appearance.titleTextAttributes[.font] = uiFont(.headline, .medium, typeface: typeface, compatibleWith: traits)
        appearance.largeTitleTextAttributes[.font] = uiFont(.largeTitle, .bold, typeface: typeface, compatibleWith: traits)
        return appearance
    }

    @MainActor
    static func tabAppearance(from original: UITabBarAppearance, typeface: AppTypeface,
                              compatibleWith traits: UITraitCollection? = nil) -> UITabBarAppearance {
        let appearance = original.copy() as! UITabBarAppearance
        let font = tabTitleFont(typeface: typeface, compatibleWith: traits)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [item.normal, item.selected, item.disabled, item.focused] {
                state.titleTextAttributes[.font] = font
            }
        }
        return appearance
    }

    @MainActor
    private static func tabTitleFont(typeface: AppTypeface, compatibleWith traits: UITraitCollection?) -> UIFont {
        let base = uiFont(fixed: 10, .medium, typeface: typeface)
        return UIFontMetrics(forTextStyle: .caption2).scaledFont(for: base, compatibleWith: traits)
    }

    private static func resolvedWeight(for style: Font.TextStyle, _ weight: Font.Weight?) -> Font.Weight {
        weight ?? (style == .headline ? .medium : .regular)
    }

    private static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .body: return .body
        case .callout: return .callout
        case .subheadline: return .subheadline
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }

    private static func uiWeight(for weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        default: return .black
        }
    }
}

extension Font {
    /// The selected typeface at a text style, scaling with Dynamic Type.
    ///
    /// `.headline` carries semibold in Apple's styles, so it defaults to medium
    /// here -- that is also what the Android text appearance uses.
    static func ax(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        ax(style, weight, preferences: .shared)
    }

    /// Injectable store for previews/tests; the default helper takes the same path.
    static func ax(_ style: Font.TextStyle, _ weight: Font.Weight? = nil, preferences: AppTypefacePreferences) -> Font {
        ax(style, weight, typeface: preferences.typeface)
    }

    /// Explicit choice for previews and tests without accessing device preferences.
    static func ax(_ style: Font.TextStyle, _ weight: Font.Weight? = nil, typeface: AppTypeface) -> Font {
        let resolved = weight ?? (style == .headline ? .medium : .regular)
        switch typeface {
        case .roboto:
            return .custom(AppFont.name(for: resolved), size: AppFont.size(of: style), relativeTo: style)
        case .sfPro:
            return .system(style, design: .default).weight(resolved)
        }
    }

    /// The selected typeface at a fixed point size, for the few places that need one.
    static func ax(fixed size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        ax(fixed: size, weight, preferences: .shared)
    }

    static func ax(fixed size: CGFloat, _ weight: Font.Weight = .regular, preferences: AppTypefacePreferences) -> Font {
        ax(fixed: size, weight, typeface: preferences.typeface)
    }

    static func ax(fixed size: CGFloat, _ weight: Font.Weight = .regular, typeface: AppTypeface) -> Font {
        switch typeface {
        case .roboto: return .custom(AppFont.name(for: weight), fixedSize: size)
        case .sfPro: return .system(size: size, weight: weight, design: .default)
        }
    }
}

@MainActor
private struct AnixartTypographyModifier: ViewModifier {
    @AppStorage(AppFont.preferenceStorageKey) private var storedTypeface = AppTypeface.roboto.rawValue
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let preferences = AppTypefacePreferences.shared
        let typeface = preferences.typeface
        content
            .environment(\.font, .ax(.body, typeface: typeface))
            .onChange(of: storedTypeface, initial: true) { _, _ in preferences.reload() }
            .onChange(of: typeface, initial: true) { _, _ in refreshBars() }
            .onChange(of: dynamicTypeSize) { _, _ in refreshBars() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                preferences.reload()
                refreshBars()
            }
    }

    private func refreshBars() {
        // Run after SwiftUI's current update so new/updated UIKit bars are in the
        // window hierarchy. Read the latest choice, not a queued stale selection.
        DispatchQueue.main.async { AppFont.applyToUIKitBars() }
    }
}

extension View {
    /// Tracks device-local font changes for stock controls and UIKit bars. Existing
    /// explicit `.ax` calls track the same preference through Observation, without
    /// any `.id` changes that would discard TabView/NavigationStack state.
    @MainActor
    func anixartTypography() -> some View {
        modifier(AnixartTypographyModifier())
    }
}
