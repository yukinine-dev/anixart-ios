import Foundation
import AnixartKit

/// Builds the URL the Kodik advert page is actually opened at.
///
/// `KodikAdActivity` does not load the episode's URL. It drops the query, writes
/// what is left percent-encoded onto a base URL from the server's config, and
/// appends the app's versionCode:
///
///     loadUrl(kodikAdIframeUrl + urlencode(scheme://host/path) + "&v=" + versionCode)
///
/// Opening the episode URL directly is what produced "данной страницы не
/// существует": that page is not meant to be opened by a client, and the advert
/// callback belongs to the wrapper, not to it.
enum KodikWrapper {
    /// Hostings this applies to, as `Parser.KODIK_URL` lists them.
    static let hosts = ["kodik.cc", "kodik.info", "aniqit.com", "kodikplayer.com"]

    static func handles(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Nil when the server has not told us where the wrapper is, which is the
    /// one thing this cannot be invented for.
    static func url(for episode: URL, base: String?) -> URL? {
        guard let base, !base.isEmpty else { return nil }

        var bare = URLComponents()
        bare.scheme = episode.scheme
        bare.host = episode.host()
        bare.path = episode.path()
        guard let stripped = bare.url?.absoluteString else { return nil }

        // The wrapper takes the URL as a query value, so everything reserved
        // has to be escaped -- `/` and `:` included, which `urlQueryAllowed`
        // leaves alone.
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        guard let encoded = stripped.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }

        return URL(string: "\(base)\(encoded)&v=\(AnixartEnvironment.versionCode)")
    }
}
