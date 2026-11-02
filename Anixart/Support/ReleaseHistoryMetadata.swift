import Foundation
import AnixartKit

enum ReleaseHistoryMetadata {
    static let recentInterval: TimeInterval = 24 * 60 * 60

    static func viewedAt(_ release: Release, now: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        guard let date = release.lastViewedDate else { return nil }
        let age = now.timeIntervalSince(date)
        // Small negative values tolerate clock skew; genuinely future dates stay
        // absolute instead of being disguised as a past view.
        guard age >= -60, age < recentInterval else { return Format.dateTime(date, timeZone: timeZone) }
        switch max(0, age) {
        case ..<60: return "только что"
        case ..<120: return "минуту назад"
        case ..<3600: return "\(Int(age / 60)) мин назад"
        case ..<7200: return "час назад"
        default: return "\(Int(age / 3600)) ч назад"
        }
    }

    static func subtitle(_ release: Release, now: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        let parts = [release.lastViewedEpisodeText, viewedAt(release, now: now, timeZone: timeZone)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
