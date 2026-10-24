// Generated from Anixart CollectionResponse (com.swiftsoft.anixartd.network.response.collection.CollectionResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct CollectionResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var collection: ReleaseCollection?
    public var completedCount: Int?
    public var droppedCount: Int?
    public var holdOnCount: Int?
    public var planCount: Int?
    public var watchingCount: Int?

    public enum CodingKeys: String, CodingKey {
        case code
        case collection
        case completedCount = "completed_count"
        case droppedCount = "dropped_count"
        case holdOnCount = "hold_on_count"
        case planCount = "plan_count"
        case watchingCount = "watching_count"
    }
}
