// Generated from Anixart ScheduleResponse (com.swiftsoft.anixartd.network.response.ScheduleResponse).
// JSON keys taken verbatim from the APK's Jackson @JsonProperty annotations.
// Do not edit by hand -- see Tools/generate-models.py in the repo root.

import Foundation

public struct ScheduleResponse: Codable, Hashable, Sendable {
    /// Anixart status code. `0` is success; see `AnixartStatus`.
    public var code: Int?
    public var friday: [Release]?
    public var monday: [Release]?
    public var saturday: [Release]?
    public var sunday: [Release]?
    public var thursday: [Release]?
    public var tuesday: [Release]?
    public var wednesday: [Release]?

    public enum CodingKeys: String, CodingKey {
        case code
        case friday
        case monday
        case saturday
        case sunday
        case thursday
        case tuesday
        case wednesday
    }
}
