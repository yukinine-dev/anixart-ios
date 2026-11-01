import Foundation
import AnixartKit

/// Settings behind Главная that belong to the device rather than the account.
///
/// The custom tab is deliberately local: the Android app says as much on the screen
/// itself -- "Изменения будут доступны только на этом устройстве" -- and stores it in
/// its own database rather than sending it to the server. The default tab is the same
/// kind of per-device preference, set by long-pressing a tab.
@MainActor
@Observable
final class HomePreferences {
    private enum Key {
        static let customFilter = "home.customFilter"
        static let customTabName = "home.customTabName"
        static let defaultTab = "home.defaultTab"
    }

    private let defaults: UserDefaults

    /// `nil` until the user configures the custom tab, which is what drives its
    /// empty state.
    private(set) var customFilter: CustomTabFilter?
    private(set) var customTabName: String
    private(set) var defaultTab: HomeTab

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.customFilter = Self.decode(from: defaults)
        self.customTabName = defaults.string(forKey: Key.customTabName) ?? ""
        self.defaultTab = defaults.string(forKey: Key.defaultTab)
            .flatMap(HomeTab.init(storageKey:)) ?? .anime
    }

    var customTabTitle: String {
        customTabName.isEmpty ? HomeTab.custom.title : customTabName
    }

    var isCustomTabConfigured: Bool { customFilter != nil }

    func save(customFilter filter: CustomTabFilter?) {
        customFilter = filter
        if let filter, let data = try? JSONEncoder().encode(filter) {
            defaults.set(data, forKey: Key.customFilter)
        } else {
            defaults.removeObject(forKey: Key.customFilter)
        }
    }

    func rename(customTabTo name: String) {
        customTabName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(customTabName, forKey: Key.customTabName)
    }

    func setDefaultTab(_ tab: HomeTab) {
        defaultTab = tab
        defaults.set(tab.storageKey, forKey: Key.defaultTab)
    }

    private static func decode(from defaults: UserDefaults) -> CustomTabFilter? {
        guard let data = defaults.data(forKey: Key.customFilter) else { return nil }
        return try? JSONDecoder().decode(CustomTabFilter.self, from: data)
    }
}

/// What the user picked in "Настройки вкладки".
///
/// The original custom settings form has four fields, not the complete filter.
/// Legacy extended keys remain Codable for previously saved alpha data, but are
/// not silently applied as constraints that this form cannot display or edit.
struct CustomTabFilter: Codable, Hashable, Sendable {
    var country: String = ""
    var category: ReleaseCategory?
    var status: AiringStatus?
    var genres: [String] = []
    var genresMode: GenresMode = .all
    var profileListExclusions: [ProfileListStatus] = []
    var types: [Int] = []
    var studio: String = ""
    var source: SourceMaterial?
    var startYear: Int?
    var endYear: Int?
    var episodes: EpisodeCountPreset?
    var episodeDuration: EpisodeDurationPreset?
    var season: ReleaseSeason?
    var ageRatings: [Int] = []
    var sort: CatalogSort = .dateUpdateDescending

    var filterRequest: FilterRequest {
        FilterRequest(
            category: category,
            country: country,
            genres: genres.isEmpty ? nil : genres,
            genresMode: genres.isEmpty ? nil : .any,
            profileListExclusions: profileListExclusions.isEmpty ? nil : profileListExclusions
        ).normalized
    }

    /// How many constraints are set, for the badge on the filter button.
    var activeCount: Int {
        filterRequest.activeConstraintCount
    }
}

extension HomeTab {
    var storageKey: String {
        switch self {
        case .custom: return "custom"
        case .anime: return "anime"
        case .donghua: return "donghua"
        case .latest: return "latest"
        case .ongoing: return "ongoing"
        case .announced: return "announced"
        case .finished: return "finished"
        case .movies: return "movies"
        case .ova: return "ova"
        }
    }

    init?(storageKey: String) {
        guard let match = HomeTab.allCases.first(where: { $0.storageKey == storageKey }) else {
            return nil
        }
        self = match
    }
}
