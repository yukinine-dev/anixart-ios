// Generated from Anixart PopularComment (com.swiftsoft.anixartd.database.entity.comment.PopularComment).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct PopularComment: Codable, Hashable, Sendable, Identifiable {
    public var id: Int?
    public var message: String?
    public var profile: ProfileSlim?
    public var timestamp: Int?
    public var voteCount: Int?

    public enum CodingKeys: String, CodingKey {
        case id
        case message
        case profile
        case timestamp
        case voteCount = "vote_count"
    }
}
