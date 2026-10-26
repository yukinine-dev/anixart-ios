import Foundation
import AnixartKit
import os

/// Decides whether a URL is something AVFoundation can actually play.
///
/// `Episode.iframe` was used for this and it does not mean that. Libria's
/// "non-iframe" URL is literally `.../public/iframe.php` serving `text/html`,
/// and Sibnet's is `shell.php`; both are the hosting's player page. Handing
/// those to AVPlayer is what produced a black screen.
///
/// So nothing is assumed from the flag: the first bytes are fetched the way a
/// player would fetch them and the container is identified by its own
/// signature, which also beats trusting a `Content-Type` these hostings set
/// carelessly.
enum StreamProbe {
    private static let log = Logger(subsystem: "app.anixart.client", category: "player")

    /// Answers cached per URL for the life of the process; a hosting's shape
    /// does not change between two taps.
    private static let cache = Cache()

    private actor Cache {
        private var entries: [URL: Bool] = [:]

        func value(for url: URL) -> Bool? { entries[url] }
        func store(_ value: Bool, for url: URL) { entries[url] = value }
    }

    static func isPlayable(_ url: URL) async -> Bool {
        if let cached = await cache.value(for: url) { return cached }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Only enough to see the container's signature.
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        // Several hostings refuse a request without it, as they do for the
        // web player.
        request.setValue(AnixartEnvironment.webBaseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 12

        var playable = false
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                playable = isMediaContainer(data)
            }
        } catch {
            log.notice("stream probe failed for \(url.host() ?? "?", privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        await cache.store(playable, for: url)
        return playable
    }

    /// MP4/MOV carry `ftyp` at offset 4; an HLS playlist starts with `#EXTM3U`.
    /// Matroska starts with its own magic and AVFoundation cannot open it at
    /// all, so it is rejected along with everything unrecognised.
    static func isMediaContainer(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        guard bytes.count >= 8 else { return false }

        if Array(bytes[4..<8]) == Array("ftyp".utf8) { return true }
        if data.prefix(7) == Data("#EXTM3U".utf8) { return true }
        return false
    }
}
