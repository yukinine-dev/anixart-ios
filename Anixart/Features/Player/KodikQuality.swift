import Foundation
import AnixartKit

/// The qualities Kodik can play for one episode.
///
/// Kodik's page loads a single manifest, for whichever quality it chose, so the
/// stream the advert gate captures has no ladder inside it. Its CDN names the
/// manifests by height (`…/720.mp4:hls:manifest.m3u8`), so the other heights sit
/// next to it. Each neighbour is asked for before it is offered: a height the
/// episode does not have simply never shows up in the menu, and an address that
/// does not follow that shape leaves the player exactly as it was.
enum KodikQuality {
    private static let heights = [1080, 720, 480, 360]

    /// Tallest first. Always contains `url` itself.
    static func variants(for url: URL) async -> [StreamVariant] {
        let text = url.absoluteString
        guard let range = text.range(of: #"/\d{3,4}\.mp4"#, options: .regularExpression) else {
            return [StreamVariant(url: url)]
        }
        let digits = text[range].dropFirst().prefix(while: \.isNumber)
        guard let currentHeight = Int(String(digits)) else { return [StreamVariant(url: url)] }

        var found = [StreamVariant(url: url, height: currentHeight)]
        await withTaskGroup(of: StreamVariant?.self) { group in
            for height in heights where height != currentHeight {
                let candidate = text.replacingCharacters(in: range, with: "/\(height).mp4")
                guard let sibling = URL(string: candidate) else { continue }
                group.addTask {
                    await isPlaylist(sibling) ? StreamVariant(url: sibling, height: height) : nil
                }
            }
            for await variant in group {
                if let variant { found.append(variant) }
            }
        }
        return found.sorted { ($0.height ?? 0) > ($1.height ?? 0) }
    }

    /// Only the first bytes: enough to see an HLS playlist's signature.
    private static func isPlaylist(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue(KodikWrapper.referer.absoluteString, forHTTPHeaderField: "Referer")
        request.timeoutInterval = 6
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return false }
        return data.prefix(7) == Data("#EXTM3U".utf8)
    }
}
