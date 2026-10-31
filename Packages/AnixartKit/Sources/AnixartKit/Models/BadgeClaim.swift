import Foundation

public struct BadgeClaimPreviewResponse: Codable, Hashable, Sendable, AnixartResponse {
    public var code: Int?
    public var achievement: BadgeClaimPreview?
}

public struct BadgeClaimPreview: Codable, Hashable, Sendable {
    public var badge: Badge?
    public var name: String?
}

public enum BadgeClaimCode {
    public static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let code: String
        if let url = URL(string: trimmed), let host = url.host {
            guard host.lowercased() == AnixartEnvironment.webBaseURL.host,
                  url.scheme == "https" || url.scheme == "http" else { return nil }
            code = url.lastPathComponent
        } else {
            code = trimmed
        }
        guard !code.isEmpty, code.utf16.count <= 256,
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return code
    }
}
