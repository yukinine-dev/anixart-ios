import Foundation

/// `comments_preview` contains release, collection and article comments. Decoding
/// them all as ReleaseComment discarded their parent and made navigation incorrect.
public struct ProfileComment: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var profile: ProfileCompact?
    public var message: String?
    public var timestamp: Int?
    public var parentCommentId: Int?
    public var replyCount: Int?
    public var vote: Int?
    public var voteCount: Int?
    public var likesCount: Int?
    public var type: Int?
    public var canLike: Bool?
    public var isDeleted: Bool?
    public var isEdited: Bool?
    public var isReply: Bool?
    public var isSpoiler: Bool?
    public var postedAtEpisode: Int?
    public var release: Embedded<Release>?
    public var collection: Embedded<ReleaseCollection>?
    public var article: Embedded<Article>?

    public enum CodingKeys: String, CodingKey {
        case id, profile, message, timestamp, type, vote, postedAtEpisode
        case replyCount = "reply_count"
        case likesCount = "likes_count"
        case parentCommentId = "parent_comment_id"
        case voteCount = "vote_count"
        case canLike = "can_like"
        case isDeleted = "is_deleted"
        case isEdited = "is_edited"
        case isReply = "is_reply"
        case isSpoiler = "is_spoiler"
        case release, collection, article
    }

    /// Keeps the same thread/composer contract for the release page's legacy
    /// preview model and comments reached from a profile.
    public init(releaseComment comment: ReleaseComment) {
        id = comment.id
        profile = comment.profile
        message = comment.message
        timestamp = comment.timestamp
        parentCommentId = comment.parentCommentId
        replyCount = comment.replyCount
        vote = comment.vote
        voteCount = comment.voteCount
        likesCount = comment.likesCount
        type = comment.type
        canLike = comment.canLike
        isDeleted = comment.isDeleted
        isEdited = comment.isEdited
        isReply = comment.isReply
        isSpoiler = comment.isSpoiler
        postedAtEpisode = comment.postedAtEpisode
        release = comment.release
        collection = nil
        article = nil
    }

    public var category: ProfileCommentCategory? {
        if release?.id != nil { return .releases }
        if collection?.id != nil { return .collections }
        if article?.id != nil { return .articles }
        return nil
    }
    public var date: Date? {
        timestamp.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
    }

    public var location: ProfileCommentLocation? {
        guard let category else { return nil }
        let parentID: Int?
        switch category {
        case .releases: parentID = release?.id
        case .collections: parentID = collection?.id
        case .articles: parentID = article?.id
        }
        guard let parentID, parentID > 0 else { return nil }
        return ProfileCommentLocation(category: category, parentID: parentID)
    }

    /// Android stores the thread root, not the last reply being addressed here.
    public var threadRootID: Int {
        if let parentCommentId, parentCommentId > 0, parentCommentId != id { return parentCommentId }
        return id
    }
}

public struct ProfileCommentLocation: Codable, Hashable, Sendable {
    public var category: ProfileCommentCategory
    public var parentID: Int

    public init(category: ProfileCommentCategory, parentID: Int) {
        self.category = category
        self.parentID = parentID
    }
}

public enum ProfileCommentCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case releases = "release", collections = "collection", articles = "article"
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .releases: return "Релизы"
        case .collections: return "Коллекции"
        case .articles: return "Записи"
        }
    }
}

/// Jackson enums may arrive by name or ordinal. Preserve unknown values as well.
public enum WireEnumValue: Codable, Hashable, Sendable {
    case name(String)
    case ordinal(Int)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) { self = .ordinal(value) }
        else { self = .name(try container.decode(String.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .name(let value): try container.encode(value)
        case .ordinal(let value): try container.encode(value)
        }
    }

    public var description: String {
        switch self {
        case .name(let value): return value
        case .ordinal(let value): return String(value)
        }
    }
}
