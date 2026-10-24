import Foundation

/// `GET profile/info` -- the signed-in account's own flags.
public struct ProfileInfoResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var channelId: Int?
    public var privilegeLevel: Int?
    public var ratingScore: Int?
    public var sponsorshipExpires: Int?
    public var isPermBanned: Bool?
    public var isSponsor: Bool?

    public enum CodingKeys: String, CodingKey {
        case code
        case channelId = "channel_id"
        case privilegeLevel = "privilege_level"
        case ratingScore = "rating_score"
        case sponsorshipExpires = "sponsorship_expires"
        case isPermBanned = "is_perm_banned"
        case isSponsor = "is_sponsor"
    }
}

/// `GET notification/count` -- unread badge count.
public struct NotificationCountResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var count: Int?
}

/// `GET profile/social/{id}` -- the links a profile chose to show.
public struct ProfileSocialResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var vkPage: String?
    public var tgPage: String?
    public var ttPage: String?
    public var instPage: String?
    public var discordPage: String?

    public enum CodingKeys: String, CodingKey {
        case code
        case vkPage = "vk_page"
        case tgPage = "tg_page"
        case ttPage = "tt_page"
        case instPage = "inst_page"
        case discordPage = "discord_page"
    }
}

/// Wrapper returned when a comment is posted.
public struct CommentAddResponse<Comment: Codable & Sendable>: Codable, Sendable, AnixartResponse {
    public var code: Int?
    public var comment: Comment?
}

/// Body of `POST release/comment/add/{releaseId}`.
///
/// `CommentAddRequest` has no `@JsonProperty` annotations, so the wire names are
/// the Java field names: camelCase, unlike most of the API.
public struct CommentAddRequest: Codable, Hashable, Sendable {
    public var message: String
    public var parentCommentId: Int?
    public var replyToProfileId: Int?
    public var spoiler: Bool

    public init(message: String, parentCommentId: Int? = nil, replyToProfileId: Int? = nil, spoiler: Bool = false) {
        self.message = message
        self.parentCommentId = parentCommentId
        self.replyToProfileId = replyToProfileId
        self.spoiler = spoiler
    }
}

/// Body of `POST release/comment/edit/{commentId}`.
public struct CommentEditRequest: Codable, Hashable, Sendable {
    public var message: String
    public var spoiler: Bool

    public init(message: String, spoiler: Bool = false) {
        self.message = message
        self.spoiler = spoiler
    }
}
