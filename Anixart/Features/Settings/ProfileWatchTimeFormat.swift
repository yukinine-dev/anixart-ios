import Foundation

enum ProfileWatchTimeFormat: String, CaseIterable, Identifiable {
    case daysAndHours, hours
    static let storageKey = "appearance.profileWatchTime"
    var id: String { rawValue }
    var title: String { self == .daysAndHours ? "Дни и часы" : "Часы" }

    func text(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if self == .hours { return "~ \(Plural.hours(seconds / 3_600))" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        return days > 0 ? "~ \(Plural.days(days)) \(Plural.hours(hours))" : "~ \(Plural.hours(hours))"
    }
}
