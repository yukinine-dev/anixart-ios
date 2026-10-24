// Generated from Anixart Release (com.swiftsoft.anixartd.database.entity.release.Release).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Release: Codable, Hashable, Sendable, Identifiable {
    public var ageRating: Int?
    public var airedOnDate: Int?
    public var author: String?
    public var badgeCount: Int?
    public var badgesPreview: [Badge]?
    public var broadcast: Int?
    public var canTorlookSearch: Bool?
    public var canVideoAppeal: Bool?
    public var category: Category?
    public var collectionCount: Int?
    public var commentCount: Int?
    public var commentPerDayCount: Int?
    public var comments: [ReleaseComment]?
    public var completedCount: Int?
    public var country: String?
    public var creationDate: Int?
    public var description: String?
    public var director: String?
    public var droppedCount: Int?
    public var duration: Int?
    public var episodeLastUpdate: EpisodeUpdate?
    public var episodesReleased: Int?
    public var episodesTotal: Int?
    public var favoriteCount: Int?
    public var genres: String?
    public var grade: Double?
    public var holdOnCount: Int?
    public var id: Int
    public var image: String?
    public var lastUpdateDate: Int?
    public var lastViewEpisode: Episode?
    public var lastViewEpisodeName: String?
    public var lastViewEpisodeTypeName: String?
    public var lastViewTimestamp: Int?
    public var myVote: Int?
    public var note: String?
    public var noteBackgroundColorDark: String?
    public var noteBackgroundColorLight: String?
    public var noteTextColorDark: String?
    public var noteTextColorLight: String?
    public var planCount: Int?
    public var profileListStatus: Int?
    public var profileReleaseTypeNotificationPreferenceCount: Int?
    public var profileReleaseTypeNotificationPreferences: [ProfileReleaseTypeNotificationPreference]?
    public var rating: Int?
    public var recommendedReleases: [Release]?
    public var related: Related?
    public var relatedCount: Int?
    public var relatedReleases: [Release]?
    public var releaseDate: String?
    public var screenshotImages: [String]?
    public var season: Int?
    public var source: String?
    public var status: ReleaseStatus?
    public var statusId: Int?
    public var studio: String?
    public var titleAlt: String?
    public var titleOriginal: String?
    public var titleRu: String?
    public var translators: String?
    public var videoBanners: [ReleaseVideoBanner]?
    public var vote1Count: Int?
    public var vote2Count: Int?
    public var vote3Count: Int?
    public var vote4Count: Int?
    public var vote5Count: Int?
    public var voteCount: Int?
    public var votedAt: Int?
    public var watchingCount: Int?
    public var year: String?
    public var yourVote: Int?
    public var isAdult: Bool?
    public var isDeleted: Bool?
    public var isFavorite: Bool?
    public var isPlayDisabled: Bool?
    public var isReleaseTypeNotificationsEnabled: Bool?
    public var isRuBlocked: Bool?
    public var isThirdPartyPlatformsDisabled: Bool?
    public var isViewBlocked: Bool?
    public var isViewed: Bool?

    public enum CodingKeys: String, CodingKey {
        case ageRating = "age_rating"
        case airedOnDate = "aired_on_date"
        case author
        case badgeCount = "badge_count"
        case badgesPreview = "badges_preview"
        case broadcast
        case canTorlookSearch = "can_torlook_search"
        case canVideoAppeal = "can_video_appeal"
        case category
        case collectionCount = "collection_count"
        case commentCount = "comment_count"
        case commentPerDayCount = "comment_per_day_count"
        case comments
        case completedCount = "completed_count"
        case country
        case creationDate = "creation_date"
        case description
        case director
        case droppedCount = "dropped_count"
        case duration
        case episodeLastUpdate = "episode_last_update"
        case episodesReleased = "episodes_released"
        case episodesTotal = "episodes_total"
        case favoriteCount = "favorites_count"
        case genres
        case grade
        case holdOnCount = "hold_on_count"
        case id
        case image
        case lastUpdateDate = "last_update_date"
        case lastViewEpisode = "last_view_episode"
        case lastViewEpisodeName = "last_view_episode_name"
        case lastViewEpisodeTypeName = "last_view_episode_type_name"
        case lastViewTimestamp = "last_view_timestamp"
        case myVote = "my_vote"
        case note
        case noteBackgroundColorDark = "note_background_color_dark"
        case noteBackgroundColorLight = "note_background_color_light"
        case noteTextColorDark = "note_text_color_dark"
        case noteTextColorLight = "note_text_color_light"
        case planCount = "plan_count"
        case profileListStatus = "profile_list_status"
        case profileReleaseTypeNotificationPreferenceCount = "profile_release_type_notification_preference_count"
        case profileReleaseTypeNotificationPreferences = "profile_release_type_notification_preferences"
        case rating
        case recommendedReleases = "recommended_releases"
        case related
        case relatedCount = "related_count"
        case relatedReleases = "related_releases"
        case releaseDate = "release_date"
        case screenshotImages = "screenshot_images"
        case season
        case source
        case status
        case statusId = "status_id"
        case studio
        case titleAlt = "title_alt"
        case titleOriginal = "title_original"
        case titleRu = "title_ru"
        case translators
        case videoBanners = "video_banners"
        case vote1Count = "vote_1_count"
        case vote2Count = "vote_2_count"
        case vote3Count = "vote_3_count"
        case vote4Count = "vote_4_count"
        case vote5Count = "vote_5_count"
        case voteCount = "vote_count"
        case votedAt = "voted_at"
        case watchingCount = "watching_count"
        case year
        case yourVote = "your_vote"
        case isAdult = "is_adult"
        case isDeleted = "is_deleted"
        case isFavorite = "is_favorite"
        case isPlayDisabled = "is_play_disabled"
        case isReleaseTypeNotificationsEnabled = "is_release_type_notifications_enabled"
        case isRuBlocked = "is_ru_blocked"
        case isThirdPartyPlatformsDisabled = "is_tpp_disabled"
        case isViewBlocked = "is_view_blocked"
        case isViewed = "is_viewed"
    }
}
