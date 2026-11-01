import Foundation

/// Wire names come from NotificationPreferenceResponse, including its two
/// camelCase sets. These are account preferences, not device push permissions.
public struct NotificationPreferencesResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var statusPreferences: [NotificationStatusPreference]?
    public var typePreferences: [NotificationTypePreference]?
    public var isArticleNotificationsEnabled: Bool?
    public var isCommentNotificationsEnabled: Bool?
    public var isEpisodeNotificationsEnabled: Bool?
    public var isFirstEpisodeNotificationEnabled: Bool?
    public var isMyArticleCommentNotificationsEnabled: Bool?
    public var isMyCollectionCommentNotificationsEnabled: Bool?
    public var isRelatedReleaseNotificationsEnabled: Bool?
    public var isReleaseTypeNotificationsEnabled: Bool?
    public var isReportProcessNotificationsEnabled: Bool?

    private enum CodingKeys: String, CodingKey {
        case code
        case statusPreferences = "profileStatusNotificationPreferences"
        case typePreferences = "profileTypeNotificationPreferences"
        case isArticleNotificationsEnabled = "is_article_notifications_enabled"
        case isCommentNotificationsEnabled = "is_comment_notifications_enabled"
        case isEpisodeNotificationsEnabled = "is_episode_notifications_enabled"
        case isFirstEpisodeNotificationEnabled = "is_first_episode_notification_enabled"
        case isMyArticleCommentNotificationsEnabled = "is_my_article_comment_notifications_enabled"
        case isMyCollectionCommentNotificationsEnabled = "is_my_collection_comment_notifications_enabled"
        case isRelatedReleaseNotificationsEnabled = "is_related_release_notifications_enabled"
        case isReleaseTypeNotificationsEnabled = "is_release_type_notifications_enabled"
        case isReportProcessNotificationsEnabled = "is_report_process_notifications_enabled"
    }

    public func value(for flag: NotificationPreferenceFlag) -> Bool? {
        switch flag {
        case .episode: return isEpisodeNotificationsEnabled
        case .firstEpisode: return isFirstEpisodeNotificationEnabled
        case .relatedRelease: return isRelatedReleaseNotificationsEnabled
        case .article: return isArticleNotificationsEnabled
        case .comment: return isCommentNotificationsEnabled
        case .myArticleComment: return isMyArticleCommentNotificationsEnabled
        case .myCollectionComment: return isMyCollectionCommentNotificationsEnabled
        case .reportProcess: return isReportProcessNotificationsEnabled
        case .selectedReleases: return isReleaseTypeNotificationsEnabled
        }
    }
}

public struct NotificationStatusPreference: Codable, Hashable, Sendable {
    public var value: Int?
    public var status: WireEnumValue?

    public var statusID: Int? {
        if let value { return value }
        if case .ordinal(let ordinal)? = status { return ordinal }
        let names = ["FAVORITE_STATUS", "STATUS_WATCHING", "STATUS_PLAN", "STATUS_COMPLETED", "STATUS_HOLD_ON", "STATUS_DROPPED"]
        if case .name(let name)? = status { return names.firstIndex(of: name) }
        return nil
    }
}

public struct NotificationTypePreference: Codable, Hashable, Sendable {
    public var type: EpisodeType?
}

public enum NotificationPreferenceFlag: String, CaseIterable, Hashable, Sendable, Identifiable {
    case episode = "episode"
    case firstEpisode = "episode/first"
    case relatedRelease = "related/release"
    case article = "article"
    case comment = "comment"
    case myArticleComment = "my/article/comment"
    case myCollectionComment = "my/collection/comment"
    case reportProcess = "report/process"
    case selectedReleases = "selected/releases"

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .episode: return "Новые серии"
        case .firstEpisode: return "Получать одно уведомление для релиза"
        case .relatedRelease: return "Связанные релизы"
        case .article: return "Записи блогов и каналов"
        case .comment: return "Ответы на мои комментарии"
        case .myArticleComment: return "Комментарии к моим записям"
        case .myCollectionComment: return "Комментарии к моим коллекциям"
        case .reportProcess: return "Результат рассмотрения жалоб"
        case .selectedReleases: return "По выбранным релизам"
        }
    }
}

public struct NotificationStatusEditRequest: Codable, Hashable, Sendable {
    public var ids: [Int]
    public init(ids: Set<Int>) { self.ids = ids.sorted() }
    private enum CodingKeys: String, CodingKey { case ids = "profileStatusNotificationPreferences" }
}

public struct NotificationTypesEditRequest: Codable, Hashable, Sendable {
    public var ids: [Int]
    public init(ids: Set<Int>) { self.ids = ids.sorted() }
    private enum CodingKeys: String, CodingKey { case ids = "profileTypeNotificationPreferences" }
}

public struct ReleaseNotificationTypesEditRequest: Codable, Hashable, Sendable {
    public var releaseID: Int
    public var ids: [Int]
    public init(releaseID: Int, ids: Set<Int>) { self.releaseID = releaseID; self.ids = ids.sorted() }
    private enum CodingKeys: String, CodingKey {
        case releaseID = "release_id"
        case ids = "profile_release_type_notification_preferences"
    }
}

public struct ReleaseNotificationPreferencesResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var preferences: [NotificationTypePreference]?
    private enum CodingKeys: String, CodingKey {
        case code
        case preferences = "profile_release_type_notification_preferences"
    }
}

/// The API paths are confirmed statically. The Android feed did not load during
/// the audit, so exposing these does not certify its native filter appearance.
public enum NotificationFeedFilter: String, CaseIterable, Hashable, Sendable, Identifiable {
    case all, episodes, friends, articles
    case relatedReleases = "related/release"
    case releaseComments = "releaseComments"
    case collectionComments = "collectionComments"
    case articleComments = "article/comments"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return "Все"
        case .episodes: return "Новые серии"
        case .friends: return "Друзья"
        case .articles: return "Записи"
        case .relatedReleases: return "Связанные релизы"
        case .releaseComments: return "Ответы к релизам"
        case .collectionComments: return "Ответы к коллекциям"
        case .articleComments: return "Ответы к записям"
        }
    }
}
