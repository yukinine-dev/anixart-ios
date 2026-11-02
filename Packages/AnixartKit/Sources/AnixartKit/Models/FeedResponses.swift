import Foundation

/// FeedSearchResponse's four independently paged envelopes, as declared in the APK.
/// Counts belong to their respective envelopes, not to a guessed global total.
public struct FeedSearchResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var channels: PageableResponse<Channel>?
    public var blogs: PageableResponse<Channel>?
    public var articles: PageableResponse<Article>?
    public var tags: PageableResponse<String>?
}

/// `feed/latest` deliberately uses camelCase `articleId`, unlike most feed fields.
public struct LatestArticleResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var articleId: Int?
}

public struct SubscriptionCountResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var subscriptionCount: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case subscriptionCount = "subscription_count"
    }
}
