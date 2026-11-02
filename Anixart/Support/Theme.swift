import SwiftUI
import UIKit
import AnixartKit

/// Visual constants, kept in one place so screens stay consistent.
enum Theme {
    /// Dynamic native colours keep modal controls and explicit Font/Color callers
    /// on the selected device-local theme, not the old placeholder violet.
    static var accent: Color { themeColor(\.accent) }
    static var background: Color { themeColor(\.background) }
    static var surface: Color { themeColor(\.surface) }
    static var raisedSurface: Color { themeColor(\.raisedSurface) }
    static var selection: Color { themeColor(\.selection) }
    private static func themeColor(_ key: KeyPath<AppThemePalette, ThemeRGB>) -> Color {
        Color(uiColor: UIColor { traits in AppThemePalette.current(dark: traits.userInterfaceStyle == .dark)[keyPath: key].uiColor })
    }

    enum Poster {
        /// Anixart posters are 3:4.
        static let aspectRatio: CGFloat = 3.0 / 4.0
        static let cornerRadius: CGFloat = 10
        static let gridWidth: CGFloat = 112
        static let rowWidth: CGFloat = 76
    }

    enum Spacing {
        static let section: CGFloat = 24
        static let row: CGFloat = 12
        static let inline: CGFloat = 6
        /// Gap between labels in the Главная tab strip. The Android strip leaves
        /// roughly 30dp between labels; 18 read as cramped next to it.
        static let tabGap: CGFloat = 28
    }

    /// The outline of the НОВИНКА badge in the voice-over picker (`colors.xml`: red).
    static let newBadge = Color(red: 0xff / 255, green: 0x60 / 255, blue: 0x5b / 255)

    /// The crown next to a sponsor's login.
    static let sponsorGold = Color(red: 0.97, green: 0.79, blue: 0.16)

    /// The five watch-list colours, taken from `colors.xml` in the APK, which the
    /// profile donut and its legend both use.
    static func listColor(_ status: ProfileListStatus) -> Color {
        switch status {
        case .watching: return Color(red: 0x73 / 255, green: 0xc9 / 255, blue: 0x78 / 255)
        case .plan: return Color(red: 0xc3 / 255, green: 0x73 / 255, blue: 0xc9 / 255)
        case .completed: return Color(red: 0x69 / 255, green: 0x79 / 255, blue: 0xce / 255)
        case .holdOn: return Color(red: 0xff / 255, green: 0xd4 / 255, blue: 0x68 / 255)
        case .dropped: return Color(red: 0xff / 255, green: 0x60 / 255, blue: 0x5b / 255)
        }
    }

    /// Colour for a rating out of 5, so a score reads at a glance.
    static func ratingColor(_ grade: Double) -> Color {
        switch grade {
        case 4.25...: return Color(red: 0.18, green: 0.70, blue: 0.40)
        case 3.5..<4.25: return Color(red: 0.55, green: 0.70, blue: 0.20)
        case 2.5..<3.5: return Color(red: 0.90, green: 0.68, blue: 0.15)
        default: return Color(red: 0.85, green: 0.30, blue: 0.25)
        }
    }
}
