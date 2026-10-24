import Foundation

/// `Profile.friendStatus` in the Android client is a Java enum
/// (`PENDING_FIRST_SECOND`, `PENDING_SECOND_FIRST`, `FRIEND`) carrying an `int value`.
///
/// Jackson will accept either the name or the ordinal for such an enum, and the APK
/// does not pin the wire form down, so this decodes both and keeps the raw value
/// when it is neither.
public enum FriendStatusCode: Codable, Hashable, Sendable {
    /// We sent the request; they have not answered.
    case requestSent
    /// They sent the request; we have not answered.
    case requestReceived
    case friend
    case none
    case unknown(String)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            switch intValue {
            case 0: self = .none
            case 1: self = .requestSent
            case 2: self = .requestReceived
            case 3: self = .friend
            default: self = .unknown(String(intValue))
            }
            return
        }
        let raw = try container.decode(String.self)
        switch raw.uppercased() {
        case "PENDING_FIRST_SECOND": self = .requestSent
        case "PENDING_SECOND_FIRST": self = .requestReceived
        case "FRIEND": self = .friend
        case "NONE", "": self = .none
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encode(0)
        case .requestSent: try container.encode(1)
        case .requestReceived: try container.encode(2)
        case .friend: try container.encode(3)
        case .unknown(let raw): try container.encode(raw)
        }
    }
}
