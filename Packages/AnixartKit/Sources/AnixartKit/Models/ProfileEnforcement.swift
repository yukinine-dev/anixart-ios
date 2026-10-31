import Foundation

/// Jackson uses `type`, not the @JsonIgnore entityType/targetEntityType fields.
/// The base class alone omits the expiry and the edited entity of every subtype.
public struct ProfileEnforcement: Codable, Hashable, Sendable, Identifiable {
    public var appealExpiresTimestamp: Int?
    public var appealProcessMessage: String?
    public var appealProcessTimestamp: Int?
    public var appealStatus: WireEnumValue?
    public var appealSubmitTimestamp: Int?
    public var appealType: WireEnumValue?
    public var creationTimestamp: Int?
    public var id: Int
    public var reason: String?
    public var revocationTimestamp: Int?
    public var isRevoked: Bool?
    public var type: String
    public var expirationTimestamp: Int?
    public var entityId: Int?
    public var entity: ProfileEnforcementEntity?
    public var changes: [ProfileEnforcementChange]?

    public enum CodingKeys: String, CodingKey {
        case appealExpiresTimestamp = "appeal_expires_timestamp"
        case appealProcessMessage = "appeal_process_message"
        case appealProcessTimestamp = "appeal_process_timestamp"
        case appealStatus = "appeal_status"
        case appealSubmitTimestamp = "appeal_submit_timestamp"
        case appealType = "appeal_type"
        case creationTimestamp = "creation_timestamp"
        case id
        case reason
        case revocationTimestamp = "revocation_timestamp"
        case isRevoked = "is_revoked"
        case type, entity, changes
        case expirationTimestamp = "expiration_timestamp"
        case entityId = "entity_id"
    }
}

extension ProfileEnforcement {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        creationTimestamp = try values.decodeIfPresent(Int.self, forKey: .creationTimestamp)
        isRevoked = try values.decodeIfPresent(Bool.self, forKey: .isRevoked)
        revocationTimestamp = try values.decodeIfPresent(Int.self, forKey: .revocationTimestamp)
        expirationTimestamp = try values.decodeIfPresent(Int.self, forKey: .expirationTimestamp)
        appealType = try values.decodeIfPresent(WireEnumValue.self, forKey: .appealType)
        appealStatus = try values.decodeIfPresent(WireEnumValue.self, forKey: .appealStatus)
        appealExpiresTimestamp = try values.decodeIfPresent(Int.self, forKey: .appealExpiresTimestamp)
        appealSubmitTimestamp = try values.decodeIfPresent(Int.self, forKey: .appealSubmitTimestamp)
        appealProcessTimestamp = try values.decodeIfPresent(Int.self, forKey: .appealProcessTimestamp)
        appealProcessMessage = try values.decodeIfPresent(String.self, forKey: .appealProcessMessage)
        entityId = try values.decodeIfPresent(Int.self, forKey: .entityId)
        changes = try values.decodeIfPresent([ProfileEnforcementChange].self, forKey: .changes)
        if values.contains(.entity), try !values.decodeNil(forKey: .entity) {
            entity = try ProfileEnforcementEntity.decode(from: values.superDecoder(forKey: .entity), type: type)
        } else { entity = nil }
    }

    public var contentID: Int? { entityId ?? entity?.id }

    public var commentCategory: ProfileCommentCategory? {
        switch type {
        case "release_comment_edit": return .releases
        case "collection_comment_edit": return .collections
        case "article_comment_edit": return .articles
        default: return nil
        }
    }

    public var title: String {
        switch type {
        case "profile_ban": return "Блокировка аккаунта"
        case "channel_suspension": return "Ограничение канала"
        case "channel_mute": return "Скрытие канала"
        case "collection_edit": return "Изменение коллекции"
        case "article_edit": return "Изменение записи"
        case "release_comment_edit", "collection_comment_edit", "article_comment_edit": return "Изменение комментария"
        default: return "Нарушение"
        }
    }

    public func isExpired(at date: Date = .now) -> Bool {
        guard let expirationTimestamp, expirationTimestamp > 0 else { return false }
        return TimeInterval(expirationTimestamp) <= date.timeIntervalSince1970
    }
}

/// Relations may be an object or an ID. Unknown/sparse future payloads remain
/// available instead of making the whole violation history fail to decode.
public enum ProfileEnforcementEntity: Encodable, Hashable, Sendable {
    case collection(Embedded<ReleaseCollection>)
    case article(ArticleReference)
    case comment(Embedded<ProfileComment>)
    case unknown(ArticleJSONValue)

    public var id: Int? {
        switch self {
        case .collection(let value): return value.id
        case .article(let value): return value.id
        case .comment(let value): return value.id
        case .unknown: return nil
        }
    }

    static func decode(from decoder: any Decoder, type: String) throws -> Self {
        let value = try decoder.singleValueContainer()
        switch type {
        case "collection_edit":
            if let entity = try? value.decode(Embedded<ReleaseCollection>.self) { return .collection(entity) }
        case "article_edit":
            if let entity = try? value.decode(ArticleReference.self) { return .article(entity) }
        case "release_comment_edit", "collection_comment_edit", "article_comment_edit":
            if let entity = try? value.decode(Embedded<ProfileComment>.self) { return .comment(entity) }
        default: break
        }
        return .unknown(try value.decode(ArticleJSONValue.self))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .collection(let entity): try entity.encode(to: encoder)
        case .article(let entity): try entity.encode(to: encoder)
        case .comment(let entity): try entity.encode(to: encoder)
        case .unknown(let entity): try entity.encode(to: encoder)
        }
    }
}

public enum ProfileEnforcementChange: Codable, Hashable, Sendable {
    case deletion(Bool)
    case spoiler(Bool)
    case unknown(ArticleJSONValue)

    private enum CodingKeys: String, CodingKey {
        case type
        case newValue = "new_value"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let type = try values.decodeIfPresent(String.self, forKey: .type)
        if let value = try? values.decode(Bool.self, forKey: .newValue) {
            if type == "is_deleted" { self = .deletion(value); return }
            if type == "is_spoiler" { self = .spoiler(value); return }
        }
        self = .unknown(try ArticleJSONValue(from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .deletion(let value), .spoiler(let value):
            var values = encoder.container(keyedBy: CodingKeys.self)
            let type: String
            if case .deletion = self { type = "is_deleted" } else { type = "is_spoiler" }
            try values.encode(type, forKey: .type)
            try values.encode(value, forKey: .newValue)
        case .unknown(let value): try value.encode(to: encoder)
        }
    }

    public var title: String {
        switch self {
        case .deletion(true): return "Контент удалён"
        case .deletion(false): return "Контент восстановлен"
        case .spoiler(true): return "Добавлена отметка «Спойлер»"
        case .spoiler(false): return "Снята отметка «Спойлер»"
        case .unknown: return "Контент изменён модератором"
        }
    }
}
