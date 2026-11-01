import Foundation

/// comments_sort.xml and its listeners use 1/2/3, not the old port's 0/1/2.
/// Replies default to oldest; profile categories and full lists default to newest.
public enum ProfileCommentSort: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case newest = 1, oldest = 2, popular = 3
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .newest: return "Сначала новые"
        case .oldest: return "Сначала старые"
        case .popular: return "Сначала популярные"
        }
    }
}

public enum ProfileVoterFilter: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case all = 0, negative = 1, positive = 2
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .all: return "Все оценки"
        case .negative: return "Только отрицательные"
        case .positive: return "Только положительные"
        }
    }
}

extension Profile {
    /// Privacy removes unavailable tabs, rather than rendering six empty tabs.
    public var visibleSections: [ProfileSection] {
        ProfileSection.allCases.filter { section in
            switch section {
            case .statistics, .votes: return isStatsHidden != true
            case .collections, .comments, .videos: return isCountsHidden != true
            case .badges: return true
            }
        }
    }

    public var hasHiddenProfileSections: Bool { isStatsHidden == true || isCountsHidden == true }

    public func friendRelationship(viewerID: Int?) -> ProfileFriendRelationship {
        guard let viewerID, viewerID != id else { return .none }
        return friendStatus?.relationship(firstID: viewerID, secondID: id) ?? .none
    }
}

/// Both send and remove return the server's new status. Hide has no new status.
public struct ProfileFriendResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var friendStatus: FriendStatusCode?
    private enum CodingKeys: String, CodingKey {
        case code
        case friendStatus = "friend_status"
    }
}

public enum ProfileFriendRelationship: Sendable, Equatable {
    case none, friend, incoming, outgoing
}

public enum ProfileCapabilities {
    /// Current reputation gates new resources, never reads/edits of an existing blog.
    /// The server remains authoritative; 3 is only the observed fallback.
    public static func minimumBlogReputation(toggles: TogglesResponse?) -> Int {
        max(0, toggles?.minBlogCreateRatingScore ?? ProfileEditorRules.minimumCoverReputation)
    }

    public static func mayCreateBlog(reputation: Int?, toggles: TogglesResponse?) -> Bool {
        (reputation ?? 0) >= minimumBlogReputation(toggles: toggles)
    }

    public static func mayUseIncognito(privilegeLevel: Int?) -> Bool { (privilegeLevel ?? 1) >= 2 }
    public static func mayModerate(viewerLevel: Int?, targetLevel: Int?) -> Bool {
        (viewerLevel ?? 1) >= 3 && (targetLevel ?? 1) <= 1
    }
}
