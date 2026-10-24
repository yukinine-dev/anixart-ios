import Foundation

/// Anixart answers with HTTP 200 and signals failure through a `code` field in the
/// body, so every response carries one. Mirrors `com.swiftsoft.anixartd.network.Response`.
public enum AnixartStatus {
    public static let successful = 0
    public static let failed = 1
    public static let banned = 402
    public static let permBanned = 403

    // auth/signIn
    public static let invalidLogin = 2
    public static let invalidPassword = 3
}

/// A response envelope carrying Anixart's `code` field.
public protocol AnixartResponse: Decodable {
    var code: Int? { get }
}

extension AnixartResponse {
    public var isSuccess: Bool { (code ?? AnixartStatus.successful) == AnixartStatus.successful }
}
