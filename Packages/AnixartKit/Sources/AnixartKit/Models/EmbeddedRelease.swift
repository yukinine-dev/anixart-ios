import Foundation

/// `ReleaseComment.release` is a Room relation in the Android client, and the
/// server sends it in two shapes:
///
///   - `discover/comments` sends the whole release object, so a comment read
///     outside its own release page still says which release it belongs to;
///   - the comments inlined into `release/{id}?extended_mode=true` send the bare
///     release id instead, since the page already knows the release.
///
/// Decoding only the object shape is what made the release page fail against
/// live data ("Expected to decode Dictionary<String, Any> but found number"),
/// so this accepts either and reports whichever arrived.
public struct EmbeddedRelease: Codable, Hashable, Sendable {
    /// The release itself, when the server sent the whole object.
    public var value: Release?
    /// The release id, which is present either way.
    public var id: Int?

    public init(value: Release? = nil, id: Int? = nil) {
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
        self.init(value: try container.decode(Release.self))
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
