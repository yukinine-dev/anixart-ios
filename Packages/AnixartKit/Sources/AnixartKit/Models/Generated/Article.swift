// Generated from Anixart Article (com.swiftsoft.anixartd.database.entity.article.Article).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Article: Codable, Hashable, Sendable, Identifiable {
    public var author: ProfileSlim?
    public var channel: Channel?
    public var commentCount: Int?
    public var containsRepostArticle: Bool?
    public var creationDate: Int?
    public var hasDeleteEnforcement: Bool?
    public var id: Int
    public var lastUpdateDate: Int?
    public var payload: ArticlePayload?
    public var popularComment: PopularComment?
    public var repostArticle: ArticleReference?
    public var repostCount: Int?
    public var vote: Int?
    public var voteCount: Int?
    public var isDeleted: Bool?
    public var isMuted: Bool?
    public var isPinned: Bool?
    public var isSigned: Bool?

    public enum CodingKeys: String, CodingKey {
        case author
        case channel
        case commentCount = "comment_count"
        case containsRepostArticle = "contains_repost_article"
        case creationDate = "creation_date"
        case hasDeleteEnforcement = "has_delete_enforcement"
        case id
        case lastUpdateDate = "last_update_date"
        case payload
        case popularComment = "popular_comment"
        case repostArticle = "repost_article"
        case repostCount = "repost_count"
        case vote
        case voteCount = "vote_count"
        case isDeleted = "is_deleted"
        case isMuted = "is_muted"
        case isPinned = "is_pinned"
        case isSigned = "is_signed"
    }
}
