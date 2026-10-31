import Foundation

/// Reposts can contain the original article or just its ID. Indirection makes
/// the recursive Article value legal without discarding the original content.
public indirect enum ArticleReference: Codable, Hashable, Sendable {
    case object(Article)
    case identifier(Int)
    case empty

    public var value: Article? {
        if case .object(let article) = self { return article }
        return nil
    }

    public var id: Int? {
        switch self {
        case .object(let article): return article.id
        case .identifier(let id): return id
        case .empty: return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .empty }
        else if let id = try? value.decode(Int.self) { self = .identifier(id) }
        else { self = .object(try value.decode(Article.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let article): try value.encode(article)
        case .identifier(let id): try value.encode(id)
        case .empty: try value.encodeNil()
        }
    }
}
