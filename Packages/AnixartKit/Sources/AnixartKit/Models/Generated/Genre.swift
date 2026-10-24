// Generated from Anixart Genre (com.swiftsoft.anixartd.database.entity.release.Genre).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Genre: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var name: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}
