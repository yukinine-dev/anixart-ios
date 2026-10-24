// Generated from Anixart Search (com.swiftsoft.anixartd.database.entity.Search).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Search: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var query: String?
    public var tsLastRequest: Int?

    public enum CodingKeys: String, CodingKey {
        case id
        case query
        case tsLastRequest
    }
}
