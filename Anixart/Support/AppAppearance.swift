import SwiftUI
import UIKit

enum AppVisualTheme: String, CaseIterable, Identifiable {
    case original, accented, oled, monet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Оригинальная"
        case .accented: return "Акцентная"
        case .oled: return "OLED — чистый чёрный"
        case .monet: return "Monet-style"
        }
    }
    var detail: String {
        switch self {
        case .original: return "Нейтральные поверхности и лавандовый акцент Anixart."
        case .accented: return "Цветные элементы и мягко окрашенные поверхности."
        case .oled: return "Чёрный фон и тёмные карточки. Эта тема всегда тёмная."
        case .monet: return "Тональная палитра из выбранного акцента. Цвета обоев Android/iOS не считываются."
        }
    }
    static func stored(_ value: String?) -> AppVisualTheme { value.flatMap(Self.init(rawValue:)) ?? .original }
    func colorScheme(normal: ColorScheme?) -> ColorScheme? { self == .oled ? .dark : normal }
}

enum AppAccentChoice: String, CaseIterable, Identifiable {
    case anixart, lavender, carmine, blue, green, amber
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anixart: return "По умолчанию Anixart"
        case .lavender: return "Лаванда Anixart"
        case .carmine: return "Кармин Anixart"
        case .blue: return "Синий"
        case .green: return "Зелёный"
        case .amber: return "Янтарный"
        }
    }
    var seed: ThemeRGB {
        switch self {
        case .anixart, .lavender: return ThemeRGB(0x6750A4)
        case .carmine: return ThemeRGB(0xF04E5C)
        case .blue: return ThemeRGB(0x1565C0)
        case .green: return ThemeRGB(0x26743B)
        case .amber: return ThemeRGB(0x936000)
        }
    }
    static func stored(_ value: String?) -> AppAccentChoice { value.flatMap(Self.init(rawValue:)) ?? .anixart }
}

struct ThemeRGB: Equatable {
    let red: Double, green: Double, blue: Double
    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    init(red: Double, green: Double, blue: Double) { self.red = red; self.green = green; self.blue = blue }
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    func mixed(with other: ThemeRGB, amount: Double) -> ThemeRGB {
        let t = min(1, max(0, amount))
        return ThemeRGB(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                        blue: blue + (other.blue - blue) * t)
    }
    var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    func contrast(with other: ThemeRGB) -> Double { (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05) }
}

struct AppThemePalette: Equatable {
    let isOLED: Bool
    let background: ThemeRGB
    let surface: ThemeRGB
    let raisedSurface: ThemeRGB
    let text: ThemeRGB
    let secondaryText: ThemeRGB
    let accent: ThemeRGB
    let selection: ThemeRGB

    static func make(theme: AppVisualTheme, accent choice: AppAccentChoice, dark requestedDark: Bool) -> AppThemePalette {
        let dark = requestedDark || theme == .oled
        let black = ThemeRGB(0x000000), white = ThemeRGB(0xFFFFFF)
        // Accent mode defaults to the APK's carmine, normal mode to lavender.
        // A separately chosen lavender remains a real override, not a hidden swap.
        let effectiveChoice: AppAccentChoice = choice == .anixart && theme == .accented ? .carmine : choice
        let seed = effectiveChoice.seed
        let neutral = dark ? ThemeRGB(0x121212) : white
        let neutralSurface = dark ? ThemeRGB(0x252525) : ThemeRGB(0xF5F5F5)
        let foreground = dark ? ThemeRGB(0xE0E0E0) : ThemeRGB(0x212121)
        let primary: ThemeRGB
        if effectiveChoice == .anixart || effectiveChoice == .lavender { primary = dark ? ThemeRGB(0xE8DEF8) : seed }
        else { primary = dark ? seed.mixed(with: white, amount: 0.48) : seed.mixed(with: black, amount: 0.18) }
        let background: ThemeRGB, surface: ThemeRGB, raised: ThemeRGB
        switch theme {
        case .original:
            background = neutral; surface = neutralSurface; raised = dark ? ThemeRGB(0x303030) : white
        case .oled:
            background = black; surface = ThemeRGB(0x101010); raised = ThemeRGB(0x191919)
        case .accented:
            background = neutral.mixed(with: seed, amount: dark ? 0.08 : 0.035)
            surface = neutralSurface.mixed(with: seed, amount: dark ? 0.14 : 0.075)
            raised = neutralSurface.mixed(with: seed, amount: dark ? 0.2 : 0.11)
        case .monet:
            // iOS has no wallpaper-derived Android Monet palette. This is an
            // explicitly named tonal approximation driven by a local seed.
            background = neutral.mixed(with: seed, amount: dark ? 0.11 : 0.06)
            surface = neutralSurface.mixed(with: seed, amount: dark ? 0.2 : 0.12)
            raised = neutralSurface.mixed(with: seed, amount: dark ? 0.27 : 0.17)
        }
        return AppThemePalette(isOLED: theme == .oled, background: background, surface: surface, raisedSurface: raised,
                               text: foreground, secondaryText: foreground.mixed(with: background, amount: 0.3),
                               accent: primary, selection: theme == .accented || theme == .monet ? primary : foreground)
    }

    static func current(dark: Bool, defaults: UserDefaults = .standard) -> AppThemePalette {
        make(theme: AppVisualTheme.stored(defaults.string(forKey: DeviceAppearancePreferenceKey.visualTheme)),
             accent: AppAccentChoice.stored(defaults.string(forKey: DeviceAppearancePreferenceKey.accent)), dark: dark)
    }
}

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue = AppThemePalette.make(theme: .original, accent: .anixart, dark: false)
}
extension EnvironmentValues {
    var appThemePalette: AppThemePalette {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }
}

@MainActor
private struct AppAppearanceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(DeviceAppearancePreferenceKey.visualTheme) private var theme = AppVisualTheme.original.rawValue
    @AppStorage(DeviceAppearancePreferenceKey.accent) private var accent = AppAccentChoice.anixart.rawValue

    private var palette: AppThemePalette {
        AppThemePalette.make(theme: AppVisualTheme.stored(theme), accent: AppAccentChoice.stored(accent), dark: scheme == .dark)
    }
    func body(content: Content) -> some View {
        content
            .environment(\.appThemePalette, palette)
            .tint(palette.accent.color)
            .scrollContentBackground(.hidden)
            .background(palette.background.color.ignoresSafeArea())
            .task(id: palette) {
                // Do not mutate UIKit while SwiftUI is updating a sheet/picker.
                await Task.yield()
                guard !Task.isCancelled else { return }
                AppThemeUIKit.apply(palette: palette)
            }
    }
}

@MainActor
private struct AppColorSchemeModifier: ViewModifier {
    @AppStorage(DeviceAppearancePreferenceKey.colorScheme) private var preference = AppColorSchemePreference.system.rawValue
    @AppStorage(DeviceAppearancePreferenceKey.visualTheme) private var theme = AppVisualTheme.original.rawValue
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(AppVisualTheme.stored(theme).colorScheme(
                normal: (AppColorSchemePreference(rawValue: preference) ?? .system).colorScheme(lowPower: lowPower)))
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    @MainActor func anixartAppearance() -> some View { modifier(AppAppearanceModifier()) }
    // A settings sheet owns its style preference instead of propagating it through
    // the presenting TabView during dismissal. Neither modifier changes view IDs.
    @MainActor func anixartColorScheme() -> some View { modifier(AppColorSchemeModifier()) }
}

/// Colour-only changes preserve the font attributes installed by AppFont.
@MainActor
enum AppThemeUIKit {
    private static let navigationTemplate: UINavigationBarAppearance = {
        let value = UINavigationBarAppearance()
        value.configureWithOpaqueBackground()
        return value
    }()
    private static let tabTemplate: UITabBarAppearance = {
        let value = UITabBarAppearance()
        value.configureWithOpaqueBackground()
        return value
    }()

    static func apply(palette: AppThemePalette) {
        // UIAppearance is setter-only. Start from owned templates, never getters
        // on a proxy, and compose font-only copies before colour-only copies.
        let navAppearance = navigation(AppFont.navigationAppearance(from: navigationTemplate, typeface: AppFont.typeface), palette: palette)
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        let tabAppearance = tabs(AppFont.tabAppearance(from: tabTemplate, typeface: AppFont.typeface), palette: palette)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITableView.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = palette.surface.uiColor
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.backgroundColor = palette.background.uiColor
                if let root = window.rootViewController { update(root, palette: palette) }
            }
        }
    }

    static func navigation(_ source: UINavigationBarAppearance, palette: AppThemePalette) -> UINavigationBarAppearance {
        let value = source.copy() as? UINavigationBarAppearance ?? UINavigationBarAppearance()
        value.backgroundEffect = nil
        value.backgroundColor = palette.background.uiColor
        value.shadowColor = palette.secondaryText.uiColor.withAlphaComponent(0.12)
        value.titleTextAttributes[.foregroundColor] = palette.text.uiColor
        value.largeTitleTextAttributes[.foregroundColor] = palette.text.uiColor
        return value
    }

    static func tabs(_ source: UITabBarAppearance, palette: AppThemePalette) -> UITabBarAppearance {
        let value = source.copy() as? UITabBarAppearance ?? UITabBarAppearance()
        value.backgroundEffect = nil
        value.backgroundColor = (palette.isOLED ? palette.background : palette.surface).uiColor
        for layout in [value.stackedLayoutAppearance, value.inlineLayoutAppearance, value.compactInlineLayoutAppearance] {
            layout.normal.iconColor = palette.secondaryText.uiColor
            layout.normal.titleTextAttributes[.foregroundColor] = palette.secondaryText.uiColor
            layout.selected.iconColor = palette.accent.uiColor
            layout.selected.titleTextAttributes[.foregroundColor] = palette.accent.uiColor
        }
        return value
    }

    /// Update bars only. SwiftUI owns its hosting/transition and collection views;
    /// walking and clearing those views during a theme change can leave blank UI.
    static func update(_ controller: UIViewController, palette: AppThemePalette) {
        if controller.isViewLoaded, let navigationController = controller as? UINavigationController {
            let bar = navigationController.navigationBar
            let value = navigation(bar.standardAppearance, palette: palette)
            bar.standardAppearance = value; bar.scrollEdgeAppearance = value; bar.compactAppearance = value
            bar.compactScrollEdgeAppearance = value
            bar.tintColor = palette.accent.uiColor
        } else if controller.isViewLoaded, let tabsController = controller as? UITabBarController {
            let bar = tabsController.tabBar
            let value = tabs(bar.standardAppearance, palette: palette)
            bar.standardAppearance = value; bar.scrollEdgeAppearance = value
            bar.tintColor = palette.accent.uiColor
        }
        for child in controller.children { update(child, palette: palette) }
        if let presented = controller.presentedViewController { update(presented, palette: palette) }
    }
}
