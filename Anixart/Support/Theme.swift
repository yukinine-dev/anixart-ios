import SwiftUI

/// Visual constants, kept in one place so screens stay consistent.
enum Theme {
    /// Anixart's accent, sampled from the Android app's primary colour.
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.91)

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
