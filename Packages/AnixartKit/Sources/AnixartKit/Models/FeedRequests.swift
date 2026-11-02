import Foundation

/// Body of `search/channels`. `query` and `permission` remain plain keys;
/// the two Boolean fields have Jackson's snake_case names.
public struct ChannelsSearchRequest: Codable, Hashable, Sendable {
    public var query: String?
    public var permission: Int?
    public var isBlog: Bool?
    public var isSubscribed: Bool?

    public init(query: String? = nil, permission: Int? = nil, isBlog: Bool? = nil, isSubscribed: Bool? = nil) {
        self.query = query
        self.permission = permission
        self.isBlog = isBlog
        self.isSubscribed = isSubscribed
    }

    public enum CodingKeys: String, CodingKey {
        case query, permission
        case isBlog = "is_blog"
        case isSubscribed = "is_subscribed"
    }
}

/// `channel/all` has a distinct filter body, including sort and no query.
public struct ChannelsFilterRequest: Codable, Hashable, Sendable {
    public var permission: Int?
    public var sort: Int?
    public var isBlog: Bool?
    public var isSubscribed: Bool?

    public init(permission: Int? = nil, sort: Int? = 1, isBlog: Bool? = nil, isSubscribed: Bool? = nil) {
        self.permission = permission
        self.sort = sort
        self.isBlog = isBlog
        self.isSubscribed = isSubscribed
    }

    public enum CodingKeys: String, CodingKey {
        case permission, sort
        case isBlog = "is_blog"
        case isSubscribed = "is_subscribed"
    }
}

/// `search/articles` uses channel_id=0 for the global article search, and a real
/// channel ID for a channel-local search. It is not a title-search scope value.
public struct ArticlesSearchRequest: Codable, Hashable, Sendable {
    public var channelId: Int
    public var query: String

    public init(query: String, channelId: Int = 0) {
        self.query = query
        self.channelId = channelId
    }

    public enum CodingKeys: String, CodingKey {
        case query
        case channelId = "channel_id"
    }
}

/// FeedFilterDateModel's switch: this is a period preset, NOT a Unix timestamp.
public enum FeedDatePeriod: Int, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case latest = 0, day = 1, week = 2, month = 3, year = 4, allTime = 5
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .latest: return "Последнее"
        case .day: return "24 часа"
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .year: return "Год"
        case .allTime: return "Всё время"
        }
    }
}

public struct FeedFilter: Hashable, Sendable {
    public var channelID: Int?
    public var date: Int

    public init(channelID: Int? = nil, date: Int = 0) {
        self.channelID = channelID
        self.date = date
    }

    public var validationMessage: String? {
        if let channelID, channelID <= 0 { return "Не удалось выбрать канал." }
        if FeedDatePeriod(rawValue: date) == nil { return "Выберите период просмотра ленты." }
        return nil
    }

    public var period: FeedDatePeriod { FeedDatePeriod(rawValue: date) ?? .latest }
}
