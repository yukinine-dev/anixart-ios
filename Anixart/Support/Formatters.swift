import Foundation

enum Format {
    /// 1 234 / 12,3 тыс. / 1,2 млн -- matches how the Android app abbreviates counts.
    static func count(_ value: Int?) -> String {
        guard let value else { return "0" }
        switch abs(value) {
        case 1_000_000...:
            return decimal(Double(value) / 1_000_000) + " млн"
        case 10_000...:
            return decimal(Double(value) / 1_000) + " тыс."
        default:
            return number.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }

    /// "118K", "10K", "910" -- the short view counts the voice-over picker shows.
    static func compactCount(_ value: Int?) -> String {
        guard let value else { return "0" }
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return "\(value / 1_000)K"
        default: return "\(value / 1_000_000)M"
        }
    }

    static func relativeDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    static func date(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dayMonthYear.string(from: date)
    }

    /// `1:23:45` or `4:05`, for player positions.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let (hours, minutes, secs) = (total / 3600, (total % 3600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// `24 мин.` episode length.
    static func episodeDuration(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return "\(minutes) мин."
    }

    private static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    private static let number: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{2009}"   // thin space, as in the Android UI
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let dayMonthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        return formatter
    }()
}
