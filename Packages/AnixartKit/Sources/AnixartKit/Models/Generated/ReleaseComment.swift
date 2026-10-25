// Generated from Anixart ReleaseComment (com.swiftsoft.anixartd.database.entity.comment.release.ReleaseComment).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseComment: Codable, Hashable, Sendable, Identifiable {
    public var canLike: Bool?
    public var id: Int
    public var likesCount: Int?
    public var message: String?
    public var parentCommentId: Int?
    public var profile: ProfileCompact?
    public var replyCount: Int?
    public var timestamp: Int?
    public var type: Int?
    public var vote: Int?
    public var voteCount: Int?
    public var isDeleted: Bool?
    public var isEdited: Bool?
    public var isReply: Bool?
    public var isSpoiler: Bool?
    public var postedAtEpisode: Int?
    public var release: EmbeddedRelease?

    public enum CodingKeys: String, CodingKey {
        case canLike = "can_like"
        case id
        case likesCount = "likes_count"
        case message
        case parentCommentId = "parent_comment_id"
        case profile
        case replyCount = "reply_count"
        case timestamp
        case type
        case vote
        case voteCount = "vote_count"
        case isDeleted = "is_deleted"
        case isEdited = "is_edited"
        case isReply = "is_reply"
        case isSpoiler = "is_spoiler"
        case postedAtEpisode
        case release
    }
}
