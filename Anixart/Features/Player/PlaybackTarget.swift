import Foundation
import AnixartKit

/// What the players are actually given for one episode.
///
/// Anixart serves no video itself -- every hosting it lists answers with its own
/// player page -- so a target is built in this order: the URL Anixart gave, when
/// it really is a stream; otherwise whatever a source that publishes its own
/// streams can supply for the same episode; otherwise nothing, and only the web
/// player is left.
struct PlaybackTarget: Sendable, Equatable {
    /// Tallest first. Empty means no stream was found for this episode.
    var variants: [StreamVariant] = []
    /// Named in the player when the stream did not come from the hosting the
    /// user picked, so it is not passed off as if it had.
    var streamSourceName: String?
    /// The hosting's own page. The web player can always show this.
    var pageURL: URL?
    /// Some hosts refuse a request without one.
    var referer: URL?

    var supportsDirectPlayback: Bool { !variants.isEmpty }
}

/// Resolves that target, once per episode URL.
///
/// Both the episode list (to decide which players to offer) and the launcher
/// (to open one) need the answer, and it costs a request or two, so it is
/// cached here rather than worked out twice.
actor PlaybackResolver {
    static let shared = PlaybackResolver()

    private var cache: [URL: PlaybackTarget] = [:]
    private var inFlight: [URL: Task<PlaybackTarget, Never>] = [:]

    func target(for episode: Episode) async -> PlaybackTarget {
        guard let url = episode.playbackURL else { return PlaybackTarget() }
        return await target(for: url, episodeNumber: episode.position)
    }

    func target(for url: URL, episodeNumber: Int?) async -> PlaybackTarget {
        if let cached = cache[url] { return cached }
        if let existing = inFlight[url] { return await existing.value }

        let task = Task<PlaybackTarget, Never> { await Self.resolve(url, episodeNumber: episodeNumber) }
        inFlight[url] = task
        let target = await task.value
        inFlight[url] = nil
        cache[url] = target
        return target
    }

    private static func resolve(_ url: URL, episodeNumber: Int?) async -> PlaybackTarget {
        if await StreamProbe.isPlayable(url) {
            return PlaybackTarget(
                variants: [StreamVariant(url: url)],
                pageURL: url,
                referer: AnixartEnvironment.webBaseURL
            )
        }

        let request = StreamRequest(anixartURL: url, episodeNumber: episodeNumber)
        if let offer = await StreamResolver.shared.offer(for: request) {
            return PlaybackTarget(
                variants: offer.variants,
                streamSourceName: offer.sourceName,
                pageURL: url,
                referer: offer.referer
            )
        }

        return PlaybackTarget(pageURL: url)
    }
}
