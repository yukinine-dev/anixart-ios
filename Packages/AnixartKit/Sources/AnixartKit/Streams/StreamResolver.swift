import Foundation

/// Finds a stream for an episode Anixart will only give a player page for.
///
/// Anixart serves no video of its own: every hosting it lists answers with its
/// own player, which is why the built-in player had nothing to open. The way
/// out is to recognise which hosting an episode sits on and ask that service's
/// own public API for the stream. Each source decides for itself whether it
/// recognises an episode, so adding one is adding one file.
public actor StreamResolver {
    public static let shared = StreamResolver()

    private let sources: [any StreamSource]
    /// Answers are per episode URL and worth keeping: the user switches hosting
    /// and comes back, and the picker asks about every episode on the screen.
    private var cache: [StreamRequest: StreamOffer?] = [:]

    public init(sources: [any StreamSource] = [AniLibriaStreamSource()]) {
        self.sources = sources
    }

    /// The first source that recognises the episode wins. Nil means none did.
    public func offer(for request: StreamRequest) async -> StreamOffer? {
        if let cached = cache[request] { return cached }

        for source in sources {
            guard let offer = try? await source.offer(for: request), !offer.variants.isEmpty else { continue }
            cache[request] = offer
            return offer
        }
        // `cache[request] = nil` would delete the entry; this records the
        // answer that no source recognised it.
        cache.updateValue(nil, forKey: request)
        return nil
    }
}
