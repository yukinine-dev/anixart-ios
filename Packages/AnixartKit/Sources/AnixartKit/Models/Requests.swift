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

    public init(
        sort: CatalogSort? = .dateUpdateDescending,
        categoryId: Int? = nil,
        statusId: Int? = nil,
        season: ReleaseSeason? = nil,
        startYear: Int? = nil,
        endYear: Int? = nil,
        episodesFrom: Int? = nil,
        episodesTo: Int? = nil,
        episodeDurationFrom: Int? = nil,
        episodeDurationTo: Int? = nil,
        country: String? = nil,
        studio: String? = nil,
        source: String? = nil,
        genres: [String]? = nil,
        genresMode: GenresMode? = nil,
        types: [Int]? = nil,
        ageRatings: [Int]? = nil,
        profileListExclusions: [ProfileListStatus]? = nil
    ) {
        self.sort = sort?.rawValue
        self.categoryId = categoryId
        self.statusId = statusId
        self.season = season?.rawValue
        self.startYear = startYear
        self.endYear = endYear
        self.episodesFrom = episodesFrom
        self.episodesTo = episodesTo
        self.episodeDurationFrom = episodeDurationFrom
        self.episodeDurationTo = episodeDurationTo
        self.country = country
        self.studio = studio
        self.source = source
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
