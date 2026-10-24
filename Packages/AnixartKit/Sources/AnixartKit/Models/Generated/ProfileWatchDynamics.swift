// Generated from Anixart ProfileWatchDynamics (com.swiftsoft.anixartd.database.entity.profile.ProfileWatchDynamics).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ProfileWatchDynamics: Codable, Hashable, Sendable, Identifiable {
    public var count: Int?
    public var day: Int?
    public var id: Int?
    public var timestamp: Int?

    public enum CodingKeys: String, CodingKey {
        case count
        case day
        case id
        case timestamp
    }
}
