import Foundation

/// Body of `POST filter/{page}`.
///
/// Field names are the `@JsonProperty` values from `FilterRequest` in the APK.
/// Omitted (`nil`) fields are left out of the JSON entirely, which is what the
/// server expects for "no constraint".
public struct FilterRequest: Codable, Hashable, Sendable {
    public var sort: Int?
    public var categoryId: Int?
    public var statusId: Int?
    public var season: Int?
    public var startYear: Int?
    public var endYear: Int?
    public var episodesFrom: Int?
    public var episodesTo: Int?
    public var episodeDurationFrom: Int?
    public var episodeDurationTo: Int?
    public var country: String?
    public var studio: String?
    public var source: String?
    public var genres: [String]?
    public var genresMode: Int?
    public var isGenresExcludeModeEnabled: Bool?
    public var types: [Int]?
    public var ageRatings: [Int]?
    public var profileListExclusions: [Int]?

    public enum CodingKeys: String, CodingKey {
        case sort
        case categoryId = "category_id"
        case statusId = "status_id"
        case season
        case startYear = "start_year"
        case endYear = "end_year"
        case episodesFrom = "episodes_from"
        case episodesTo = "episodes_to"
        case episodeDurationFrom = "episode_duration_from"
        case episodeDurationTo = "episode_duration_to"
        case country
        case studio
        case source
        case genres
        case genresMode = "genres_mode"
        case isGenresExcludeModeEnabled = "is_genres_exclude_mode_enabled"
        case types
        case ageRatings = "age_ratings"
        case profileListExclusions = "profile_list_exclusions"
    }

    /// Builds a filter the way the Android client does, resolving the UI's presets into
    /// the explicit ranges the server expects (`CustomFilterTabPresenter`).
    public init(
        sort: CatalogSort? = .dateUpdateDescending,
        category: ReleaseCategory? = nil,
        status: AiringStatus? = nil,
        season: ReleaseSeason? = nil,
        startYear: Int? = nil,
        endYear: Int? = nil,
        episodes: EpisodeCountPreset? = nil,
        episodeDuration: EpisodeDurationPreset? = nil,
        country: String? = nil,
        studio: String? = nil,
        source: SourceMaterial? = nil,
        genres: [String]? = nil,
        genresMode: GenresMode? = nil,
        types: [Int]? = nil,
        ageRatings: [Int]? = nil,
        profileListExclusions: [ProfileListStatus]? = nil
    ) {
        self.sort = sort?.rawValue
        self.categoryId = category?.rawValue
        self.statusId = status?.rawValue
        self.season = season?.rawValue
        self.startYear = startYear
        self.endYear = endYear
        self.episodesFrom = episodes?.range.from
        self.episodesTo = episodes?.range.to
        self.episodeDurationFrom = episodeDuration?.range.from
        self.episodeDurationTo = episodeDuration?.range.to
        // Empty strings are omitted rather than sent, as the Android client does.
        self.country = (country?.isEmpty ?? true) ? nil : country
        self.studio = (studio?.isEmpty ?? true) ? nil : studio
        self.source = source?.rawValue
        self.genres = genres
        self.genresMode = genresMode?.rawValue
        self.isGenresExcludeModeEnabled = genresMode == .exclude ? true : nil
        self.types = types
        self.ageRatings = ageRatings
        self.profileListExclusions = profileListExclusions?.map(\.rawValue)
    }

    /// True when nothing but the sort order is set, so the catalogue is unfiltered.
    public var isEmpty: Bool {
        categoryId == nil && statusId == nil && season == nil && startYear == nil
            && endYear == nil && episodesFrom == nil && episodesTo == nil
            && episodeDurationFrom == nil && episodeDurationTo == nil
            && (country?.isEmpty ?? true) && (studio?.isEmpty ?? true)
            && (source?.isEmpty ?? true) && (genres?.isEmpty ?? true)
            && (types?.isEmpty ?? true) && (ageRatings?.isEmpty ?? true)
            && (profileListExclusions?.isEmpty ?? true)
    }

    /// Count constraint groups, including the fields offered by both filter UIs.
    /// Sort order alone does not make a catalogue filtered.
    public var activeConstraintCount: Int {
        [
            categoryId != nil, statusId != nil, season != nil,
            startYear != nil || endYear != nil,
            episodesFrom != nil || episodesTo != nil,
            episodeDurationFrom != nil || episodeDurationTo != nil,
            !(country?.isEmpty ?? true), !(studio?.isEmpty ?? true), !(source?.isEmpty ?? true),
            !(genres?.isEmpty ?? true), !(types?.isEmpty ?? true),
            !(ageRatings?.isEmpty ?? true), !(profileListExclusions?.isEmpty ?? true)
        ].filter { $0 }.count
    }

    /// Reject a contradictory year range instead of returning a misleading empty
    /// list. Future years are allowed for announced releases.
    public var validationMessage: String? {
        if let startYear, startYear <= 0 { return "Укажите положительный год начала." }
        if let endYear, endYear <= 0 { return "Укажите положительный год окончания." }
        if let startYear, let endYear, startYear > endYear {
            return "Год начала не может быть позже года окончания."
        }
        return nil
    }

    /// A guest has no account lists to exclude. Keep the device-local preference
    /// unchanged so signing in restores its effect.
    public var withoutProfileListExclusions: FilterRequest {
        var request = self
        request.profileListExclusions = nil
        return request
    }

    /// Canonical UI output: empty selections are absent, and deleting the last
    /// genre also removes its mode/flag rather than keeping a phantom filter.
    public var normalized: FilterRequest {
        var request = self
        request.country = Self.nonblank(country)
        request.studio = Self.nonblank(studio)
        request.source = Self.nonblank(source)
        request.genres = Self.nonemptyUnique(genres?.compactMap { Self.nonblank($0) })
        request.types = Self.nonemptyUnique(types)
        request.ageRatings = Self.nonemptyUnique(ageRatings)
        request.profileListExclusions = Self.nonemptyUnique(profileListExclusions)
        if request.genres == nil {
            request.genresMode = nil
            request.isGenresExcludeModeEnabled = nil
        } else if request.genresMode == GenresMode.exclude.rawValue || request.isGenresExcludeModeEnabled == true {
            request.genresMode = GenresMode.exclude.rawValue
            request.isGenresExcludeModeEnabled = true
        } else {
            request.isGenresExcludeModeEnabled = nil
        }
        return request
    }

    private static func nonblank(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func nonemptyUnique<Value: Hashable>(_ values: [Value]?) -> [Value]? {
        guard let values else { return nil }
        var seen = Set<Value>()
        let unique = values.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique
    }
}

/// Body of the `POST search/*` endpoints.
///
/// `SearchRequest` in the APK carries no `@JsonProperty` annotations, so the wire
/// names are the Java field names verbatim -- note `searchBy` is camelCase here
/// while most of the API is snake_case.
public struct SearchRequest: Codable, Hashable, Sendable {
    public var query: String
    public var searchBy: Int

    public init(query: String, scope: SearchScope = .all) {
        self.query = query
        self.searchBy = scope.rawValue
    }
}
