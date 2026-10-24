// Generated from Anixart ReleaseVideo (com.swiftsoft.anixartd.database.entity.release.video.ReleaseVideo).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ReleaseVideo: Codable, Hashable, Sendable, Identifiable {
    public var category: ReleaseVideoCategory?
    public var delete: Bool?
    public var favoriteCount: Int?
    public var hosting: ReleaseVideoHosting?
    public var id: Int
    public var image: String?
    public var playerUrl: String?
    public var profile: Profile?
    public var timestamp: Int?
    public var title: String?
    public var url: String?
    public var isFavorite: Bool?

    public enum CodingKeys: String, CodingKey {
        case category
        case delete
        case favoriteCount = "favorites_count"
        case hosting
        case id
        case image
        case playerUrl = "player_url"
        case profile
        case timestamp
        case title
        case url
        case isFavorite = "is_favorite"
    }
}
