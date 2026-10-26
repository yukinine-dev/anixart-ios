import Foundation

/// AniLibria, through its own public API.
///
/// Anixart's "Libria" hosting points at
/// `anixart.libria.fun/public/iframe.php?id=9307&ep=1`, and that `id` is
/// AniLibria's own release id -- 9307 is what AniLibria returns for
/// "Киберпанк: Бегущие по краю". So the stream is one documented request away:
/// no title matching, and nobody's player scraped.
public struct AniLibriaStreamSource: StreamSource {
    public let name = "AniLibria"

    /// The v3 API returns 410 now; this is the one still answering.
    static let apiBase = URL(string: "https://anilibria.top/api/v1")!
    static let referer = URL(string: "https://anilibria.top/")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func offer(for request: StreamRequest) async throws -> StreamOffer? {
        guard let reference = Reference(request.anixartURL) else { return nil }

        let release = try await fetchRelease(reference.releaseID)
        let number = reference.episodeNumber ?? request.episodeNumber
        guard let episode = release.episode(number: number) else { return nil }

        let variants = episode.streams
            .compactMap { height, path -> StreamVariant? in
                guard let url = Self.absolute(path) else { return nil }
                return StreamVariant(url: url, height: height)
            }
        guard !variants.isEmpty else { return nil }

        return StreamOffer(sourceName: name, variants: variants, referer: Self.referer)
    }

    private func fetchRelease(_ id: Int) async throws -> ReleasePayload {
        let url = Self.apiBase.appending(path: "anime/releases/\(id)")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AnixartError.http(statusCode: status, path: url.path(percentEncoded: false))
        }
        return try JSONDecoder().decode(ReleasePayload.self, from: data)
    }

    /// Paths come back either absolute or rooted at the API host.
    static func absolute(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: path, relativeTo: referer)?.absoluteURL
    }

    /// What Anixart's Libria URL says: AniLibria's release id and the episode.
    struct Reference: Equatable {
        var releaseID: Int
        var episodeNumber: Int?

        init?(_ url: URL) {
            guard let host = url.host, host.contains("libria."),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems
            else { return nil }

            func int(_ name: String) -> Int? {
                items.first { $0.name == name }?.value.flatMap(Int.init)
            }
            guard let id = int("id") else { return nil }
            self.releaseID = id
            self.episodeNumber = int("ep")
        }
    }

    // MARK: - What the API returns

    /// Only the parts the player needs. Everything is optional because this is
    /// someone else's API and a missing field should cost one episode, not the
    /// whole release.
    struct ReleasePayload: Decodable {
        var id: Int?
        var episodes: [EpisodePayload]?

        /// AniLibria orders episodes by `ordinal`; falls back to position.
        func episode(number: Int?) -> EpisodePayload? {
            guard let episodes, !episodes.isEmpty else { return nil }
            guard let number else { return episodes.first }
            if let match = episodes.first(where: { $0.ordinal.map { Int($0) } == number }) {
                return match
            }
            return episodes.indices.contains(number - 1) ? episodes[number - 1] : nil
        }
    }

    struct EpisodePayload: Decodable {
        var ordinal: Double?
        var name: String?
        var duration: Int?
        /// Picture height -> playlist, read off whatever `hls_*` keys the
        /// release carries, so a new rung needs no change here.
        var streams: [Int: String] = [:]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            for key in container.allKeys {
                let field = key.stringValue
                switch field {
                case "ordinal":
                    ordinal = try? container.decode(Double.self, forKey: key)
                case "name":
                    name = try? container.decode(String.self, forKey: key)
                case "duration":
                    duration = try? container.decode(Int.self, forKey: key)
                default:
                    guard field.hasPrefix("hls_"),
                          let height = Int(field.dropFirst("hls_".count)),
                          let path = try? container.decode(String.self, forKey: key),
                          !path.isEmpty
                    else { continue }
                    streams[height] = path
                }
            }
        }
    }
}
