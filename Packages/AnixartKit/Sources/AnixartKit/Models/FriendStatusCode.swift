import Foundation

/// `Profile.friendStatus` in the Android client is a Java enum
/// (`PENDING_FIRST_SECOND`, `PENDING_SECOND_FIRST`, `FRIEND`) carrying an `int value`.
///
/// DEX ordinals/values are 0, 1, 2. There is no zero-valued NONE entry:
/// no friendship is represented by null. Pending direction uses the two IDs.
public enum FriendStatusCode: Codable, Hashable, Sendable {
    case pendingFirstSecond
    case pendingSecondFirst
    case friend
    case none
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .none; return }
        if let intValue = try? container.decode(Int.self) {
            switch intValue {
            case 0: self = .pendingFirstSecond
            case 1: self = .pendingSecondFirst
            case 2: self = .friend
            default: self = .unknown(String(intValue))
            }
            return
        }
        let raw = try container.decode(String.self)
        switch raw.uppercased() {
        case "PENDING_FIRST_SECOND": self = .pendingFirstSecond
        case "PENDING_SECOND_FIRST": self = .pendingSecondFirst
        case "FRIEND": self = .friend
        case "NONE", "": self = .none
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encodeNil()
        case .pendingFirstSecond: try container.encode(0)
        case .pendingSecondFirst: try container.encode(1)
        case .friend: try container.encode(2)
        case .unknown(let raw): try container.encode(raw)
        }
    }

    /// ProfileFriendsState.Companion: firstID is the viewer in headers, but the
    /// list owner in recommendation rows. FIRST/SECOND refer to sorted IDs.
    public func relationship(firstID: Int, secondID: Int) -> ProfileFriendRelationship {
        switch self {
        case .friend: return .friend
        case .pendingFirstSecond: return firstID < secondID ? .outgoing : .incoming
        case .pendingSecondFirst: return firstID < secondID ? .incoming : .outgoing
        case .none, .unknown: return .none
        }
    }
}
