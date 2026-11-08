import Foundation

enum Format {
    /// The whole number with thin-space grouping ("18 129"), never abbreviated.
    /// The release page shows how many have it in favourites this way.
    static func exact(_ value: Int?) -> String {
        guard let value else { return "0" }
        return number.string(from: NSNumber(value: value)) ?? "\(value)"
    }

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

    /// «сегодня в 03:11», «вчера в 01:13», «22 авг. в 11:24», and with the year when
    /// it is not this one -- how Android dates a comment.
    static func commentDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        let time = commentTime.string(from: date)
        if calendar.isDateInToday(date) { return "сегодня в \(time)" }
        if calendar.isDateInYesterday(date) { return "вчера в \(time)" }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        return (sameYear ? commentDay : commentDayYear).string(from: date) + " в " + time
    }

    private static let commentTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private static let commentDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    private static let commentDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy 'г.'"
        return formatter
    }()

    static func relativeDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return relative.localizedString(for: date, relativeTo: .now)
    }

    static func date(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dayMonthYear.string(from: date)
    }

    /// Absolute watch-history date, including the year and local 24-hour time.
    /// Never turns an old entry into "месяц назад" or a current entry into "сегодня".
    static func dateTime(_ date: Date?, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy 'в' HH:mm"
        return formatter.string(from: date)
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
