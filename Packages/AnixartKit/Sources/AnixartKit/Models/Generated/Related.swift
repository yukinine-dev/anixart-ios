// Generated from Anixart Related (com.swiftsoft.anixartd.database.entity.release.Related).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Related: Codable, Hashable, Sendable, Identifiable {
    public var description: String?
    public var id: Int?
    public var image: String?
    public var images: [String]?
    public var nameRu: String?
    public var releaseCount: Int?

    public enum CodingKeys: String, CodingKey {
        case description
        case id
        case image
        case images
        case nameRu = "name_ru"
        case releaseCount = "release_count"
    }
}
