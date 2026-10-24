// Generated from Anixart Channel (com.swiftsoft.anixartd.database.entity.channel.Channel).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Channel: Codable, Hashable, Sendable, Identifiable {
    public var articleCount: Int?
    public var avatar: String?
    public var badgeId: Int?
    public var badgeName: String?
    public var badgeType: Int?
    public var badgeUrl: String?
    public var blockExpireDate: Int?
    public var blockReason: String?
    public var blogProfileId: Int?
    public var cover: String?
    public var creationDate: Int?
    public var description: String?
    public var episodeChannelWidgetArticleCount: Int?
    public var episodeChannelWidgetPopularityPeriod: Int?
    public var episodeChannelWidgetSort: Int?
    public var id: Int?
    public var lastArticleDate: Int?
    public var lastUpdateDate: Int?
    public var permission: Int?
    public var recentArticleCount: Int?
    public var subscriberCount: Int?
    public var title: String?
    public var isArticleSuggestionEnabled: Bool?
    public var isBlocked: Bool?
    public var isBlog: Bool?
    public var isCommentingEnabled: Bool?
    public var isDeleted: Bool?
    public var isEpisodeChannelWidgetEnabled: Bool?
    public var isLinkedToType: Bool?
    public var isMuted: Bool?
    public var isPermBlocked: Bool?
    public var isSubscribed: Bool?
    public var isVerified: Bool?

    public enum CodingKeys: String, CodingKey {
        case articleCount = "article_count"
        case avatar
        case badgeId = "channel_badge_id"
        case badgeName = "channel_badge_name"
        case badgeType = "channel_badge_type"
        case badgeUrl = "channel_badge_url"
        case blockExpireDate = "block_expire_date"
        case blockReason = "block_reason"
        case blogProfileId = "blog_profile_id"
        case cover
        case creationDate = "creation_date"
        case description
        case episodeChannelWidgetArticleCount = "episode_channel_widget_article_count"
        case episodeChannelWidgetPopularityPeriod = "episode_channel_widget_popularity_period"
        case episodeChannelWidgetSort = "episode_channel_widget_sort"
        case id
        case lastArticleDate = "last_article_date"
        case lastUpdateDate = "last_update_date"
        case permission
        case recentArticleCount = "recent_article_count"
        case subscriberCount = "subscriber_count"
        case title
        case isArticleSuggestionEnabled = "is_article_suggestion_enabled"
        case isBlocked = "is_blocked"
        case isBlog = "is_blog"
        case isCommentingEnabled = "is_commenting_enabled"
        case isDeleted = "is_deleted"
        case isEpisodeChannelWidgetEnabled = "is_episode_channel_widget_enabled"
        case isLinkedToType = "is_linked_to_type"
        case isMuted = "is_muted"
        case isPermBlocked = "is_perm_blocked"
        case isSubscribed = "is_subscribed"
        case isVerified = "is_verified"
    }
}
