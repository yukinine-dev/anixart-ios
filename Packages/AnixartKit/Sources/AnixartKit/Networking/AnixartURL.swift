import Foundation

public enum AnixartURL {
    /// Rewrites a host to its mirror, the way `Common` does in the Android app:
    /// `static.anixart.tv` becomes `mirror-static.anixart.tv`, and a bare
    /// two-label host gets a `mirror.` prefix.
    public static func mirrored(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host
        else { return url }

        let labels = host.split(separator: ".")
        if labels.count > 2 {
            components.host = "mirror-" + labels.first.map { String($0) }!
                + "." + labels.dropFirst().joined(separator: ".")
        } else {
            components.host = "mirror." + host
        }
        return components.url ?? url
    }

    /// `application/x-www-form-urlencoded` body, matching OkHttp's `FormBody`:
    /// space becomes `+` and everything outside the unreserved set is percent-escaped.
    public static func formEncoded(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func escape(_ value: String) -> String {
        value
            .addingPercentEncoding(withAllowedCharacters: unreserved)?
            .replacingOccurrences(of: "%20", with: "+")
            ?? value
    }

    /// Absolute URL for a poster, avatar or screenshot returned by the API.
    ///
    /// The API already returns absolute URLs on `static.anixart.tv`; this only
    /// applies the mirror rewrite when the server asked for it.
    public static func image(_ value: String?, useMirror: Bool = false) -> URL? {
        guard let value, !value.isEmpty, let url = URL(string: value) else { return nil }
        return useMirror ? mirrored(url) : url
    }
}
