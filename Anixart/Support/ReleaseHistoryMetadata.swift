import Foundation
import AnixartKit

enum ReleaseHistoryMetadata {
    static func subtitle(_ release: Release, timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        let parts = [release.lastViewedEpisodeText, Format.dateTime(release.lastViewedDate, timeZone: timeZone)]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
