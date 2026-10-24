import Foundation

/// Response body for the endpoints that return only `Response` -- a bare status code.
///
/// Used by `favorite/add`, `history/delete`, `type/pin`, `episode/watch` and friends,
/// all of which extend `Response` with no extra fields in the Android client.
public struct StatusResponse: Codable, Sendable, AnixartResponse {
    public var code: Int?

    public init(code: Int? = nil) {
        self.code = code
    }
}
