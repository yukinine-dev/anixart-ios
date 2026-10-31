// Generated from Anixart ProfilePreferenceResponse (com.swiftsoft.anixartd.network.response.profile.ProfilePreferenceResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfilePreferenceResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var availableThemes: [AvailableTheme]?
    public var avatar: String?
    public var badge: Badge?
    public var banChangeAvatarExpires: Int?
    public var banChangeLoginExpires: Int?
    public var channelId: Int?
    public var emailHint: String?
    public var episodeChannelWidgetsHidden: Bool?
    public var pinnedSectionId: Int?
    public var privacyCounts: Int?
    public var privacyFriendRequests: Int?
    public var privacySocial: Int?
    public var privacyStats: Int?
    public var selectedThemeId: Int?
    public var status: String?
    public var tgPage: String?
    public var vkPage: String?
    public var isChangeAvatarBanned: Bool?
    public var isChangeLoginBanned: Bool?
    public var isGoogleBound: Bool?
    public var isIncognito: Bool?
    public var isLoginChanged: Bool?
    public var isTelegramBound: Bool?
    public var isVkBound: Bool?
    public var isYandexBound: Bool?

    public enum CodingKeys: String, CodingKey {
        case code
        case availableThemes = "available_themes"
        case avatar
        case badge
        case banChangeAvatarExpires = "ban_change_avatar_expires"
        case banChangeLoginExpires = "ban_change_login_expires"
        case channelId = "channel_id"
        case emailHint = "email_hint"
        case episodeChannelWidgetsHidden = "episode_channel_widgets_hidden"
        case pinnedSectionId = "pinned_section_id"
        case privacyCounts = "privacy_counts"
        case privacyFriendRequests = "privacy_friend_requests"
        case privacySocial = "privacy_social"
        case privacyStats = "privacy_stats"
        case selectedThemeId = "selected_theme_id"
        case status
        case tgPage
        case vkPage
        case isChangeAvatarBanned = "is_change_avatar_banned"
        case isChangeLoginBanned = "is_change_login_banned"
        case isGoogleBound = "is_google_bound"
        case isIncognito = "is_incognito"
        case isLoginChanged = "is_login_changed"
        case isTelegramBound = "is_telegram_bound"
        case isVkBound = "is_vk_bound"
        case isYandexBound = "is_yandex_bound"
    }
}
