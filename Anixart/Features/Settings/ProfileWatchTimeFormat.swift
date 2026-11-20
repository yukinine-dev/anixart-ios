import Foundation

enum ProfileWatchTimeFormat: String, CaseIterable, Identifiable {
    case daysAndHours, hours
    static let storageKey = "appearance.profileWatchTime"
    var id: String { rawValue }
    var title: String { self == .daysAndHours ? "Дни и часы" : "Часы" }

    /// `watchedTime` is reported in minutes, not seconds -- treating it as
    /// seconds under-counted by 60x against the Android app's own total.
    func text(minutes totalMinutes: Int) -> String {
        let totalMinutes = max(0, totalMinutes)
        if self == .hours { return "~ \(Plural.hours(totalMinutes / 60))" }
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        return days > 0 ? "~ \(Plural.days(days)) \(Plural.hours(hours))" : "~ \(Plural.hours(hours))"
    }
}
