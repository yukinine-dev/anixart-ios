import Foundation

/// The notification feed is a polymorphic list: `ProfileNotification` in the APK is
/// annotated `@JsonTypeInfo(property = "type", use = Id.NAME)` with a
/// `defaultImpl` for unknown kinds, so an unrecognised `type` must not fail the
/// whole page. This enum mirrors that, including the fallback case.
public enum AnixartNotification: Codable, Hashable, Sendable, Identifiable {
    case episode(EpisodeNotification)
    case relatedRelease(RelatedReleaseNotification)
    case friend(FriendNotification)
    case unsupported(BaseNotification)

    public var id: Int { base.id ?? 0 }

    public var base: BaseNotification {
        switch self {
        case .episode(let value): return value.base
        case .relatedRelease(let value): return value.base
        case .friend(let value): return value.base
        case .unsupported(let value): return value
        }
    }

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decodeIfPresent(String.self, forKey: .type)
        switch type {
        case "episode":
            self = .episode(try EpisodeNotification(from: decoder))
        case "relatedRelease":
            self = .relatedRelease(try RelatedReleaseNotification(from: decoder))
        case "friend":
            self = .friend(try FriendNotification(from: decoder))
        default:
            self = .unsupported(try BaseNotification(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .episode(let value): try value.encode(to: encoder)
        case .relatedRelease(let value): try value.encode(to: encoder)
        case .friend(let value): try value.encode(to: encoder)
        case .unsupported(let value): try value.encode(to: encoder)
        }
    }

    /// Fields every notification carries (`ProfileNotification`).
    public struct BaseNotification: Codable, Hashable, Sendable {
        public var id: Int?
        public var type: String?
        public var timestamp: Int?
        public var isNew: Bool?
        public var isPushed: Bool?

        public enum CodingKeys: String, CodingKey {
            case id, type, timestamp
            case isNew = "is_new"
            case isPushed = "is_pushed"
        }

        public var date: Date? {
            guard let timestamp, timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
    }

    /// A new episode appeared for a release in the user's lists.
    public struct EpisodeNotification: Codable, Hashable, Sendable {
        public var base: BaseNotification
        public var episode: EpisodeCompact?

        private enum CodingKeys: String, CodingKey { case episode }

        public init(from decoder: any Decoder) throws {
            base = try BaseNotification(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            episode = try container.decodeIfPresent(EpisodeCompact.self, forKey: .episode)
        }

        public func encode(to encoder: any Encoder) throws {
            try base.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(episode, forKey: .episode)
        }
    }

    /// A release related to one the user follows was added.
    public struct RelatedReleaseNotification: Codable, Hashable, Sendable {
        public var base: BaseNotification
        public var release: ReleaseCompact?

        private enum CodingKeys: String, CodingKey { case release }

        public init(from decoder: any Decoder) throws {
            base = try BaseNotification(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            release = try container.decodeIfPresent(ReleaseCompact.self, forKey: .release)
        }

        public func encode(to encoder: any Encoder) throws {
            try base.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(release, forKey: .release)
        }
    }

    /// A friend request was sent, accepted or declined.
    public struct FriendNotification: Codable, Hashable, Sendable {
        public var base: BaseNotification
        public var value: Int?
        public var byProfile: ProfileSlim?

        private enum CodingKeys: String, CodingKey {
            case value
            case byProfile = "by_profile"
        }

        public init(from decoder: any Decoder) throws {
            base = try BaseNotification(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decodeIfPresent(Int.self, forKey: .value)
            byProfile = try container.decodeIfPresent(ProfileSlim.self, forKey: .byProfile)
        }

        public func encode(to encoder: any Encoder) throws {
            try base.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(value, forKey: .value)
            try container.encodeIfPresent(byProfile, forKey: .byProfile)
        }
    }
}
