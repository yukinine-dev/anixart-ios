import Foundation

/// Preferences are calculated by the server, independently of the current list
/// counts. Missing/empty groups have no row, not an "insufficient data" placeholder.
public struct ProfileStatisticsPreferences: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let title: String
        public let value: String
        public var id: String { title }
    }

    public let rows: [Row]

    public init(profile: Profile) {
        guard profile.isStatsHidden != true else { rows = []; return }
        let groups: [(String, [ProfileGenre]?)] = [
            ("Жанры:", profile.preferredGenres),
            ("Аудитория:", profile.preferredAudiences),
            ("Тематика:", profile.preferredThemes)
        ]
        rows = groups.compactMap { title, genres in
            let values = (genres ?? []).compactMap { genre -> String? in
                guard let name = genre.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                // A sparse or invalid percentage must not invent a statistic.
                guard let percentage = genre.percentage, (0...100).contains(percentage) else { return name }
                return "\(name) \(percentage)%"
            }
            guard !values.isEmpty else { return nil }
            return Row(title: title, value: values.joined(separator: ", "))
        }
    }
}
