import Foundation

/// One quality a source publishes for an episode.
///
/// Anixart's own hostings never get this far -- they serve their own player
/// pages -- so a variant always comes from a source that publishes streams
/// itself.
public struct StreamVariant: Sendable, Hashable, Identifiable, Codable {
    public var url: URL
    /// Picture height when the source names one: 1080, 720, 480.
    public var height: Int?

    public var id: String { url.absoluteString }

    /// What the quality menu shows for this rung.
    public var label: String {
        guard let height else { return "Исходное" }
        return "\(height)p"
    }

    public init(url: URL, height: Int? = nil) {
        self.url = url
        self.height = height
    }
}

/// What a source can hand the player for one episode.
public struct StreamOffer: Sendable, Hashable {
    /// Shown next to the quality menu, so a stream that did not come from the
    /// hosting the user picked is not passed off as if it had.
    public var sourceName: String
    /// Tallest first; `variants.first` is the default pick.
    public var variants: [StreamVariant]
    /// Several hosts refuse a request without one.
    public var referer: URL?

    public init(sourceName: String, variants: [StreamVariant], referer: URL? = nil) {
        self.sourceName = sourceName
        self.variants = variants.sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        self.referer = referer
    }

    public var best: StreamVariant? { variants.first }
}

/// The episode a stream is wanted for, in the terms a source can act on.
public struct StreamRequest: Sendable, Hashable {
    /// The URL Anixart gave for this episode, whatever it turns out to serve.
    /// Sources read what they recognise out of it.
    public var anixartURL: URL
    /// Episode number as Anixart counts them, used when the URL carries none.
    public var episodeNumber: Int?

    public init(anixartURL: URL, episodeNumber: Int? = nil) {
        self.anixartURL = anixartURL
        self.episodeNumber = episodeNumber
    }
}

/// A place that publishes streams through an API of its own.
public protocol StreamSource: Sendable {
    var name: String { get }

    /// Returns nil when this source does not recognise the episode. That is an
    /// answer, not a failure: the resolver simply tries the next source.
    func offer(for request: StreamRequest) async throws -> StreamOffer?
}
