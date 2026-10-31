import Foundation

/// Editor.js-style content, verified against `articles/models` in the APK.
public struct ArticlePayload: Codable, Hashable, Sendable {
    public var blocks: [ArticleBlock]?
    public var blockCount: Int?
    public var time: Int?
    public var version: String?

    enum CodingKeys: String, CodingKey {
        case blocks, time, version
        case blockCount = "block_count"
    }
}

public struct ArticleBlock: Codable, Hashable, Sendable {
    public var id: String?
    public var type: String
    public var data: ArticleBlockData?
    public var unsupportedData: ArticleJSONValue?

    enum CodingKeys: String, CodingKey { case id, type, data }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "unsupported"
        if ["paragraph", "header", "quote", "delimiter", "list", "media", "embed"].contains(type) {
            data = try values.decodeIfPresent(ArticleBlockData.self, forKey: .data)
            unsupportedData = nil
        } else {
            data = nil
            unsupportedData = try values.decodeIfPresent(ArticleJSONValue.self, forKey: .data)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encode(type, forKey: .type)
        if let data { try values.encode(data, forKey: .data) }
        else { try values.encodeIfPresent(unsupportedData, forKey: .data) }
    }
}

/// Lists carry strings in `items`, media blocks carry MediaFile objects.
public struct ArticleBlockData: Codable, Hashable, Sendable {
    public var text: String?
    public var textLength: Int?
    public var level: Int?
    public var caption: String?
    public var captionLength: Int?
    public var alignment: String?
    public var style: String?
    public var items: ArticleItems?
    public var itemCount: Int?
    public var url: String?
    public var embed: String?
    public var image: String?
    public var title: String?
    public var description: String?
    public var service: String?
    public var siteName: String?
    public var hash: String?
    public var width: Int?
    public var height: Int?

    enum CodingKeys: String, CodingKey {
        case text, level, caption, alignment, style, items, url, embed, image
        case title, description, service, hash, width, height
        case siteName = "site_name"
        case textLength = "text_length"
        case captionLength = "caption_length"
        case itemCount = "item_count"
    }
}

public enum ArticleItems: Codable, Hashable, Sendable {
    case list([String])
    case media([ArticleMediaFile])

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        if let strings = try? values.decode([String].self) { self = .list(strings) }
        else { self = .media(try values.decode([ArticleMediaFile].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        switch self {
        case .list(let items): try values.encode(items)
        case .media(let items): try values.encode(items)
        }
    }
}

public struct ArticleMediaFile: Codable, Hashable, Sendable {
    /// UUID on Android; kept as a string to tolerate future ID formats.
    public var id: String?
    public var url: String?
    public var width: Int?
    public var height: Int?
    public var hash: String?
}

/// Unknown future block data survives a decode/encode round trip.
public enum ArticleJSONValue: Codable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String)
    case array([ArticleJSONValue]), object([String: ArticleJSONValue])

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([ArticleJSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: ArticleJSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .string(let string): try value.encode(string)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        }
    }
}

public struct ArticleResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var article: Article?
}
