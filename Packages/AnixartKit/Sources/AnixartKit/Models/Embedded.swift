import Foundation

/// A relation the server sends in either of two shapes.
///
/// The Android models are Room entities, so a relation is a real object in the
/// database but is only worth putting on the wire when the caller does not
/// already have it. The server therefore sends either the whole object or the
/// bare row id, depending on the endpoint:
///
///   - `ReleaseComment.release` is the whole release on `discover/comments`, so
///     a comment read outside its own release page still says what it is about,
///     and the bare id on the comments inlined into `release/{id}`;
///   - `EpisodeSource.type` is the whole voice-over in some listings and its id
///     in others.
///
/// Decoding one shape only fails the entire response -- "Expected to decode
/// Dictionary<String, Any> but found number" -- so this accepts either and
/// reports which arrived. Use it for any relation the probe job catches.
public struct Embedded<Value>: Codable, Hashable, Sendable
where Value: Codable & Hashable & Sendable & Identifiable, Value.ID == Int {
    /// The object itself, when the server sent the whole thing.
    public var value: Value?
    /// The row id, which is present either way.
    public var id: Int?

    public init(value: Value? = nil, id: Int? = nil) {
        self.value = value
        self.id = id ?? value?.id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.init()
            return
        }
        if let id = try? container.decode(Int.self) {
            self.init(value: nil, id: id)
            return
        }
        self.init(value: try container.decode(Value.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else if let id {
            try container.encode(id)
        } else {
            try container.encodeNil()
        }
    }
}

public typealias EmbeddedRelease = Embedded<Release>
public typealias EmbeddedEpisodeType = Embedded<EpisodeType>
