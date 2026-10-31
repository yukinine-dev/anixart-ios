import Foundation

/// A single Anixart API call, typed by the response it decodes to.
///
/// Anixart's shape is unusual in two ways that this type encodes directly:
/// the session token travels as a `token` *query* parameter rather than a header,
/// and "POST" endpoints are often reads (`filter/{page}`, `search/releases/{page}`,
/// `discover/*`) whose body carries the query.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public enum Body: Sendable {
        /// `application/json` -- used by filter, search and report endpoints.
        case json(any Encodable & Sendable)
        /// `application/x-www-form-urlencoded` -- used by every `auth/*` endpoint.
        case form([String: String])
        /// `multipart/form-data` -- avatar and channel-cover uploads.
        case multipart(MultipartBody)
    }

    public var method: Method
    /// Path relative to the base URL, with no leading slash (e.g. `release/123`).
    public var path: String
    /// Query items. Entries with a `nil` value are dropped, matching Retrofit's
    /// behaviour of omitting null `@Query` parameters.
    public var query: [String: String?]
    public var body: Body?
    /// How the token is attached.
    public var auth: Auth
    public var headers: [String: String]
    /// A few reads use a business code as a normal state (deletion status uses
    /// `3` for "no request"). Mutations still accept only `0` by default.
    public var acceptedStatusCodes: Set<Int>

    public enum Auth: Sendable {
        /// No token sent.
        case none
        /// Token sent when one is stored; the call still works for guests.
        case optional
        /// Token required; the client throws `AnixartError.notAuthenticated` without one.
        case required
        /// For session-sensitive mutations, refuse to use a newer account's token.
        case matchingToken(String)
    }

    public init(
        method: Method = .get,
        path: String,
        query: [String: String?] = [:],
        body: Body? = nil,
        auth: Auth = .optional,
        headers: [String: String] = [:],
        acceptedStatusCodes: Set<Int> = [AnixartStatus.successful]
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.auth = auth
        self.headers = headers
        self.acceptedStatusCodes = acceptedStatusCodes
    }
}
