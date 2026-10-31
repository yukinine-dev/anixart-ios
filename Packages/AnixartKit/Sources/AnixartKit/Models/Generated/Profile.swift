// Generated from Anixart Profile (com.swiftsoft.anixartd.database.entity.profile.Profile).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var value: Int?
    public var avatar: String?
    public var badge: Badge?
    public var badgeCount: Int?
    public var badgeId: Int?
    public var badgeName: String?
    public var badgeType: Int?
    public var badgeUrl: String?
    public var badgesPreview: [Badge]?
    public var banExpires: Int?
    public var banReason: String?
    public var blockListAddedDate: Int?
    public var collectionCount: Int?
    public var collectionsPreview: [ReleaseCollection]?
    public var commentCount: Int?
    public var commentsPreview: [ProfileComment]?
    public var completedCount: Int?
    public var deletionDeleteAt: Int?
    public var deletionRequestedAt: Int?
    public var discordPage: String?
    public var droppedCount: Int?
    public var favoriteCount: Int?
    public var friendCount: Int?
    public var friendStatus: FriendStatusCode?
    public var friendsPreview: [Profile]?
    public var history: [Release]?
    public var holdOnCount: Int?
    public var id: Int
    public var instPage: String?
    public var lastActivityTime: Int?
    public var login: String?
    public var password: String?
    public var pinnedSectionId: Int?
    public var planCount: Int?
    public var preferredAudiences: [ProfileGenre]?
    public var preferredGenres: [ProfileGenre]?
    public var preferredThemes: [ProfileGenre]?
    public var privilegeLevel: Int?
    public var ratingScore: Int?
    public var registerDate: Int?
    public var releaseVideosPreview: [ReleaseVideo]?
    public var roles: [RoleDto]?
    public var sponsorshipExpires: Int?
    public var status: String?
    public var tgPage: String?
    public var themeAnimationEnabled: Bool?
    public var themeAnimationSpeed: String?
    public var themeBackgroundAlpha: Double?
    public var themeBackgroundMode: String?
    public var themeBackgroundUrl: String?
    public var themeEnabled: Bool?
    public var themeGradientAngle: String?
    public var themeGradientEndColor: String?
    public var themeGradientStartColor: String?
    public var themeIconAlpha: Double?
    public var themeIconColor: String?
    public var themeIconDensity: String?
    public var themeIconResName: String?
    public var themeIconSize: String?
    public var themeIconUrl: String?
    public var ttPage: String?
    public var videoCount: Int?
    public var vkPage: String?
    public var vote: Int?
    public var votes: [Release]?
    public var watchDynamics: [ProfileWatchDynamics]?
    public var watchedEpisodeCount: Int?
    public var watchedTime: Int?
    public var watchingCount: Int?
    public var isBanned: Bool?
    public var isBlocked: Bool?
    public var isCommentNotificationsEnabled: Bool?
    public var isCountsHidden: Bool?
    public var isDeleted: Bool?
    public var isDeletionRequested: Bool?
    public var isEpisodeNotificationsEnabled: Bool?
    public var isFirstEpisodeNotificationEnabled: Bool?
    public var isFriendRequestsDisallowed: Bool?
    public var isGoogleBound: Bool?
    public var isIncognito: Bool?
    public var isLoginChanged: Bool?
    public var isMeBlocked: Bool?
    public var isOnline: Bool?
    public var isPermBanned: Bool?
    public var isSocial: Bool?
    public var isSocialHidden: Bool?
    public var isSponsor: Bool?
    public var isStatsHidden: Bool?
    public var isTelegramBound: Bool?
    public var isVerified: Bool?
    public var isVkBound: Bool?
    public var isYandexBound: Bool?

    public enum CodingKeys: String, CodingKey {
        case value
        case avatar
        case badge
        case badgeCount = "badge_count"
        case badgeId = "badge_id"
        case badgeName = "badge_name"
        case badgeType = "badge_type"
        case badgeUrl = "badge_url"
        case badgesPreview = "badges_preview"
        case banExpires = "ban_expires"
        case banReason = "ban_reason"
        case blockListAddedDate = "added_date"
        case collectionCount = "collection_count"
        case collectionsPreview = "collections_preview"
        case commentCount = "comment_count"
        case commentsPreview = "comments_preview"
        case completedCount = "completed_count"
        case deletionDeleteAt = "deletion_delete_at"
        case deletionRequestedAt = "deletion_requested_at"
        case discordPage = "discord_page"
        case droppedCount = "dropped_count"
        case favoriteCount = "favorite_count"
        case friendCount = "friend_count"
        case friendStatus = "friend_status"
        case friendsPreview = "friends_preview"
        case history
        case holdOnCount = "hold_on_count"
        case id
        case instPage = "inst_page"
        case lastActivityTime = "last_activity_time"
        case login
        case password
        case pinnedSectionId = "pinned_section_id"
        case planCount = "plan_count"
        case preferredAudiences = "preferred_audiences"
        case preferredGenres = "preferred_genres"
        case preferredThemes = "preferred_themes"
        case privilegeLevel = "privilege_level"
        case ratingScore = "rating_score"
        case registerDate = "register_date"
        case releaseVideosPreview = "release_videos_preview"
        case roles
        case sponsorshipExpires
        case status
        case tgPage = "tg_page"
        case themeAnimationEnabled = "theme_animation_enabled"
        case themeAnimationSpeed = "theme_animation_speed"
        case themeBackgroundAlpha = "theme_background_alpha"
        case themeBackgroundMode = "theme_background_mode"
        case themeBackgroundUrl = "theme_background_url"
        case themeEnabled = "theme_enabled"
        case themeGradientAngle = "theme_gradient_angle"
        case themeGradientEndColor = "theme_gradient_end_color"
        case themeGradientStartColor = "theme_gradient_start_color"
        case themeIconAlpha = "theme_icon_alpha"
        case themeIconColor = "theme_icon_color"
        case themeIconDensity = "theme_icon_density"
        case themeIconResName = "theme_icon_res_name"
        case themeIconSize = "theme_icon_size"
        case themeIconUrl = "theme_icon_url"
        case ttPage = "tt_page"
        case videoCount = "video_count"
        case vkPage = "vk_page"
        case vote
        case votes
        case watchDynamics = "watch_dynamics"
        case watchedEpisodeCount = "watched_episode_count"
        case watchedTime = "watched_time"
        case watchingCount = "watching_count"
        case isBanned = "is_banned"
        case isBlocked = "is_blocked"
        case isCommentNotificationsEnabled = "is_comment_notifications_enabled"
        case isCountsHidden = "is_counts_hidden"
        case isDeleted = "is_deleted"
        case isDeletionRequested = "is_deletion_requested"
        case isEpisodeNotificationsEnabled = "is_episode_notifications_enabled"
        case isFirstEpisodeNotificationEnabled = "is_first_episode_notification_enabled"
        case isFriendRequestsDisallowed = "is_friend_requests_disallowed"
        case isGoogleBound = "is_google_bound"
        case isIncognito = "is_incognito"
        case isLoginChanged = "is_login_changed"
        case isMeBlocked = "is_me_blocked"
        case isOnline = "is_online"
        case isPermBanned = "is_perm_banned"
        case isSocial = "is_social"
        case isSocialHidden = "is_social_hidden"
        case isSponsor = "is_sponsor"
        case isStatsHidden = "is_stats_hidden"
        case isTelegramBound = "is_telegram_bound"
        case isVerified = "is_verified"
        case isVkBound = "is_vk_bound"
        case isYandexBound = "is_yandex_bound"
    }
}
