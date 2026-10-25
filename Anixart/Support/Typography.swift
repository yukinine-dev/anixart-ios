import SwiftUI
import UIKit

/// The app's typeface.
///
/// Anixart on Android styles nearly every text appearance as `sans-serif-medium`,
/// which is Roboto on stock Android, so the port ships Roboto (Apache-2.0) and
/// routes every `.font(...)` through here. The sizes are Apple's own text-style
/// sizes at the Large content size, and `relativeTo:` keeps Dynamic Type working.
///
/// `Product Sans`, which the APK bundles for a single style, is Google
/// proprietary and is not shipped -- see Anixart/Resources/Fonts/LICENSE.txt.
enum AppFont {
    static let family = "Roboto"

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
    /// SwiftUI's font modifiers do not reach the navigation and tab bars, which
    /// UIKit still draws, so those two are set through the appearance proxies.
    @MainActor
    static func applyToUIKitBars() {
        guard let medium = UIFont(name: name(for: .medium), size: 17),
              let bold = UIFont(name: name(for: .bold), size: 34)
        else { return }

        let navigation = UINavigationBarAppearance()
        navigation.configureWithDefaultBackground()
        navigation.titleTextAttributes = [.font: medium]
        navigation.largeTitleTextAttributes = [.font: bold]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        guard let caption = UIFont(name: name(for: .medium), size: 10) else { return }
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: caption]
            item.selected.titleTextAttributes = [.font: caption]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Font {
    /// Roboto at a text style, scaling with Dynamic Type.
    ///
    /// `.headline` carries semibold in Apple's styles, so it defaults to medium
    /// here -- that is also what the Android text appearance uses.
    static func ax(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let resolved = weight ?? (style == .headline ? .medium : .regular)
        return .custom(AppFont.name(for: resolved), size: AppFont.size(of: style), relativeTo: style)
    }

    /// Roboto at a fixed point size, for the few places that need one.
    static func ax(fixed size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(for: weight), fixedSize: size)
    }
}

extension View {
    /// Makes Roboto the default for everything below, so stock controls
    /// (list rows, pickers, menus) pick it up too.
    func anixartTypography() -> some View {
        environment(\.font, .ax(.body))
    }
}
