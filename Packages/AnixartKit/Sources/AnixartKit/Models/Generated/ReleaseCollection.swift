// Generated from Anixart Collection (com.swiftsoft.anixartd.database.entity.collection.Collection).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseCollection: Codable, Hashable, Sendable, Identifiable {
    public var commentCount: Int?
    public var creationDate: Int?
    public var creator: Profile?
    public var delete: Bool?
    public var description: String?
    public var favoriteCount: Int?
    public var id: Int
    public var image: String?
    public var lastUpdateDate: Int?
    public var releases: [Release]?
    public var title: String?
    public var isFavorite: Bool?
    public var isPrivate: Bool?

    public enum CodingKeys: String, CodingKey {
        case commentCount = "comment_count"
        case creationDate = "creation_date"
        case creator
        case delete
        case description
        case favoriteCount = "favorites_count"
        case id
        case image
        case lastUpdateDate = "last_update_date"
        case releases
        case title
        case isFavorite = "is_favorite"
        case isPrivate = "is_private"
    }
}
