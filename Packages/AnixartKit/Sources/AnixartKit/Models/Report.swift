import Foundation

/// Reasons are fetched separately for each target. IDs are server-owned and
/// must not be guessed from the order/names seen in the audit screenshots.
public enum ReportTargetKind: Hashable, Sendable {
    case profile, collection, article, release
    case comment(ProfileCommentCategory)

    public var path: String {
        switch self {
        case .profile: return "profile"
        case .collection: return "collection"
        case .article: return "article"
        case .release: return "release"
        case .comment(let category): return "comment/\(category.rawValue)"
        }
    }
}

public struct ReportReason: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
}

public struct ReportRequest: Codable, Hashable, Sendable {
    public var entityID: Int
    public var reasonID: Int
    public var message: String
    public init(entityID: Int, reasonID: Int, message: String) {
        self.entityID = entityID
        self.reasonID = reasonID
        self.message = message
    }
    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case reasonID = "reason"
        case message
    }
    public static let messageLimit = 400
}
