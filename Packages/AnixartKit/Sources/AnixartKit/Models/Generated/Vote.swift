// Generated from Anixart Vote (com.swiftsoft.anixartd.database.entity.Vote).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct Vote: Codable, Hashable, Sendable {
    public var ip: String?
    public var timestamp: Int?
    public var vote: Int?

    public enum CodingKeys: String, CodingKey {
        case ip
        case timestamp
        case vote
    }
}
