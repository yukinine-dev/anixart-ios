// Generated from Anixart Interesting (com.swiftsoft.anixartd.database.entity.release.Interesting).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Interesting: Codable, Hashable, Sendable, Identifiable {
    public var action: String?
    public var description: String?
    public var id: Int
    public var image: String?
    public var title: String?
    public var type: Int?
    public var isHidden: Bool?

    public enum CodingKeys: String, CodingKey {
        case action
        case description
        case id
        case image
        case title
        case type
        case isHidden
    }
}
