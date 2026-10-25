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
        customTabName = name.trimmingCharacters(in: .whitespaces)
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
/// Kept separate from `FilterRequest` because the two are not the same shape: this
/// holds the UI's presets, and `filterRequest` resolves them into the ranges the
/// server wants, exactly as `CustomFilterTabPresenter` does.
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
            sort: sort,
            category: category,
            status: status,
            season: season,
            startYear: startYear,
            endYear: endYear,
            episodes: episodes,
            episodeDuration: episodeDuration,
            country: country,
            studio: studio,
            source: source,
            genres: genres.isEmpty ? nil : genres,
            genresMode: genres.isEmpty ? nil : genresMode,
            types: types.isEmpty ? nil : types,
            ageRatings: ageRatings.isEmpty ? nil : ageRatings,
            profileListExclusions: profileListExclusions.isEmpty ? nil : profileListExclusions
        )
    }

    /// How many constraints are set, for the badge on the filter button.
    var activeCount: Int {
        var count = 0
        if !country.isEmpty { count += 1 }
        if category != nil { count += 1 }
        if status != nil { count += 1 }
        if !genres.isEmpty { count += 1 }
        if !profileListExclusions.isEmpty { count += 1 }
        if !types.isEmpty { count += 1 }
        if !studio.isEmpty { count += 1 }
        if source != nil { count += 1 }
        if startYear != nil || endYear != nil { count += 1 }
        if episodes != nil { count += 1 }
        if episodeDuration != nil { count += 1 }
        if season != nil { count += 1 }
        if !ageRatings.isEmpty { count += 1 }
        return count
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
