import Foundation

/// The server writes an object it has already written earlier in the same response
/// as just its row id (Jackson object identity, the `@id` keys in the JSON).
///
/// A profile's `collections_preview` is where it shows: the collection's `creator`
/// is a profile with its own `collections_preview`, whose first entry is the very
/// collection being decoded, and so arrives as a bare number. Decoding it as an
/// object failed the whole profile ("Expected to decode Dictionary<String, Any> but
/// found number", `profile.collections_preview[0].creator.collections_preview[0]`).
///
/// A reference becomes a collection that carries only its id, a `creator` that is
/// itself a reference is left empty, and `releases` keeps the entries that are real
/// objects. The first full copy in the response is still decoded in full.
extension ReleaseCollection {
    public init(referenceID: Int) {
        self.id = referenceID
    }

    public init(from decoder: any Decoder) throws {
        // Assigned directly rather than through `init(referenceID:)`: a delegating
        // path would make this a delegating initializer and forbid the assignments
        // below. The other properties are optional and start as nil.
        if let single = try? decoder.singleValueContainer(), let reference = try? single.decode(Int.self) {
            id = reference
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount)
        creationDate = try container.decodeIfPresent(Int.self, forKey: .creationDate)
        creator = try? container.decodeIfPresent(Profile.self, forKey: .creator)
        delete = try container.decodeIfPresent(Bool.self, forKey: .delete)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        favoriteCount = try container.decodeIfPresent(Int.self, forKey: .favoriteCount)
        id = try container.decode(Int.self, forKey: .id)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        lastUpdateDate = try container.decodeIfPresent(Int.self, forKey: .lastUpdateDate)
        releases = (try? container.decodeIfPresent([Embedded<Release>].self, forKey: .releases))?
            .compactMap(\.value)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite)
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate)
    }
}
