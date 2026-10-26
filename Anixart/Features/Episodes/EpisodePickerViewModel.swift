import Foundation
import AnixartKit

/// Playback is a three-level drill-down in Anixart and each level is its own
/// request: voice-over type -> hosting source -> episode list.
///
/// The view model keeps all three levels so the user can switch voice-over or
/// hosting without losing their place.
@MainActor
@Observable
final class EpisodePickerViewModel {
    private(set) var types: [EpisodeType] = []
    private(set) var sources: [EpisodeSource] = []
    private(set) var episodes: [Episode] = []

    /// Episodes per hosting, filled once the voice-over's sources are known.
    ///
    /// Two reasons to hold them all. Switching hosting becomes instant, and --
    /// the point -- it is the only way to know which hostings hand over a real
    /// stream, which decides whether the embedded player can be offered at all.
    private(set) var episodesBySource: [Int: [Episode]] = [:]

    private(set) var selectedType: EpisodeType?
    private(set) var selectedSource: EpisodeSource?

    private(set) var isLoadingTypes = false
    private(set) var isLoadingEpisodes = false
    private(set) var errorMessage: String?

    /// `0` ascending, `1` descending -- the `sort` query on the episodes endpoint.
    /// Changed through `toggleSortOrder()`, since `@Observable` does not track a
    /// stored property that declares a `didSet`.
    private(set) var sortDescending = false

    /// The Все / Озвучки / Субтитры filter above the voice-over list.
    private(set) var kind: Kind = .all

    enum Kind: String, CaseIterable, Identifiable {
        case all, dubs, subtitles

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "Все"
            case .dubs: return "Озвучки"
            case .subtitles: return "Субтитры"
            }
        }
    }

    private let release: Release
    private let client: AnixartClient
    private let session: SessionController

    init(release: Release, client: AnixartClient, session: SessionController) {
        self.release = release
        self.client = client
        self.session = session
    }

    /// Voice-overs known to have a hosting the built-in player can take.
    ///
    /// Filled in the background after the list appears: the user should not wait
    /// on it, and the list is useful without it.
    private(set) var playableTypeIDs: Set<Int> = []
    private(set) var isCheckingPlayability = false

    /// Whether a hosting hands over a stream turns out to be a property of the
    /// hosting itself, not of the release -- the probe in CI shows Kodik always
    /// sending a page and Sibnet, Libria, Liberty and RuTube always sending a
    /// URL. So each hosting is classified once per screen, by name, instead of
    /// fetching every voice-over's episodes.
    private var hostingGivesStream: [String: Bool] = [:]

    /// The voice-overs the current chip leaves visible.
    var visibleTypes: [EpisodeType] {
        switch kind {
        case .all: return types
        case .dubs: return types.filter { !$0.isSubtitles }
        case .subtitles: return types.filter(\.isSubtitles)
        }
    }

    func select(kind: Kind) {
        self.kind = kind
    }

    /// Re-fetches the voice-over list, for the toolbar's refresh.
    func reload() async {
        types = []
        await loadTypes()
    }

    var releaseID: Int { release.id }
    var releaseTitle: String { release.displayTitle }

    func loadTypes() async {
        guard types.isEmpty, !isLoadingTypes else { return }
        isLoadingTypes = true
        errorMessage = nil
        do {
            let response = try await client.send(EpisodeEndpoints.types(releaseID: release.id))
            types = response.types ?? []
            // Pinned voice-overs come first in the Android UI; everything else keeps
            // the order the server sent.
            types.sort { lhs, rhs in
                let lhsPinned = lhs.pinned ?? false
                let rhsPinned = rhs.pinned ?? false
                return lhsPinned && !rhsPinned
            }
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoadingTypes = false
        Task { await checkPlayability() }
    }

    /// Works out which voice-overs the built-in player can handle.
    ///
    /// Sources are cheap to list, so every voice-over's are fetched; episodes
    /// are not, so one episode list per distinct hosting is enough to classify
    /// it. Results land as they arrive, so badges appear progressively.
    private func checkPlayability() async {
        guard !isCheckingPlayability else { return }
        isCheckingPlayability = true
        defer { isCheckingPlayability = false }

        let client = self.client
        let releaseID = release.id
        let allTypes = types

        let sourcesByType = await withTaskGroup(of: (Int, [EpisodeSource]).self) { group in
            for type in allTypes {
                group.addTask {
                    let response = try? await client.send(
                        EpisodeEndpoints.sources(releaseID: releaseID, typeID: type.id)
                    )
                    return (type.id, response?.sources ?? [])
                }
            }
            var result: [Int: [EpisodeSource]] = [:]
            for await (id, sources) in group { result[id] = sources }
            return result
        }

        for (typeID, sources) in sourcesByType {
            for source in sources {
                let name = source.displayName
                if hostingGivesStream[name] == nil {
                    let response = try? await client.send(
                        EpisodeEndpoints.episodes(
                            releaseID: releaseID,
                            typeID: typeID,
                            sourceID: source.id,
                            sort: 0
                        )
                    )
                    guard let url = response?.episodes?.compactMap(\.playbackURL).first else { continue }
                    hostingGivesStream[name] = await StreamProbe.isPlayable(url)
                }
                if hostingGivesStream[name] == true {
                    playableTypeIDs.insert(typeID)
                    break
                }
            }
        }
    }

    func toggleSortOrder() async {
        sortDescending.toggle()
        // Order is just the position, so the cached list is re-sorted rather
        // than refetched.
        episodes = sorted(episodes)
    }

    func select(type: EpisodeType) async {
        selectedType = type
        sources = []
        episodes = []
        selectedSource = nil
        episodesBySource = [:]
        isLoadingEpisodes = true
        do {
            let response = try await client.send(
                EpisodeEndpoints.sources(releaseID: release.id, typeID: type.id)
            )
            let loaded = response.sources ?? []
            sources = loaded
            await loadEverySource(type: type, sources: loaded)
            await probeSources(loaded)

            // Prefer a hosting the built-in player can actually open, when one
            // exists at all.
            let preferred = loaded.first(where: hasDirectStream) ?? loaded.first
            if let preferred { await select(source: preferred) }
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoadingEpisodes = false
    }

    func select(source: EpisodeSource) async {
        selectedSource = source
        if let cached = episodesBySource[source.id] {
            episodes = sorted(cached)
        } else {
            await loadEpisodes()
        }
    }

    /// Hostings whose URLs turned out to be something AVFoundation can open.
    ///
    /// Checked by fetching the URL, not by reading `Episode.iframe`: that flag
    /// does not mean what it looks like -- Libria's "non-iframe" URL is an HTML
    /// player page.
    private(set) var playableSourceIDs: Set<Int> = []

    func hasDirectStream(_ source: EpisodeSource) -> Bool {
        playableSourceIDs.contains(source.id)
    }

    /// The hosting to point the user at when the current one is a page only.
    var sourceWithDirectStream: EpisodeSource? {
        sources.first(where: hasDirectStream)
    }

    private func loadEverySource(type: EpisodeType, sources: [EpisodeSource]) async {
        let client = self.client
        let releaseID = release.id
        let sortDescending = self.sortDescending

        let loaded = await withTaskGroup(of: (Int, [Episode]).self) { group in
            for source in sources {
                group.addTask {
                    let response = try? await client.send(
                        EpisodeEndpoints.episodes(
                            releaseID: releaseID,
                            typeID: type.id,
                            sourceID: source.id,
                            sort: sortDescending ? 1 : 0
                        )
                    )
                    return (source.id, response?.episodes ?? [])
                }
            }
            var result: [Int: [Episode]] = [:]
            for await (id, episodes) in group { result[id] = episodes }
            return result
        }
        episodesBySource = loaded
    }

    /// Asks each hosting's first episode URL what it really serves.
    private func probeSources(_ sources: [EpisodeSource]) async {
        var playable: Set<Int> = []
        for source in sources {
            guard let url = episodesBySource[source.id]?.compactMap(\.playbackURL).first else { continue }
            if await StreamProbe.isPlayable(url) { playable.insert(source.id) }
        }
        playableSourceIDs = playable
    }

    private func sorted(_ episodes: [Episode]) -> [Episode] {
        episodes.sorted {
            sortDescending
                ? ($0.position ?? 0) > ($1.position ?? 0)
                : ($0.position ?? 0) < ($1.position ?? 0)
        }
    }

    func loadEpisodes() async {
        guard let type = selectedType, let source = selectedSource else { return }
        isLoadingEpisodes = true
        errorMessage = nil
        do {
            let response = try await client.send(
                EpisodeEndpoints.episodes(
                    releaseID: release.id,
                    typeID: type.id,
                    sourceID: source.id,
                    sort: sortDescending ? 1 : 0
                )
            )
            episodes = response.episodes ?? []
            if let source = selectedSource { episodesBySource[source.id] = episodes }
        } catch {
            episodes = []
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoadingEpisodes = false
    }

    /// Marks an episode watched and flips it locally so the checkmark appears at once.
    func markWatched(_ episode: Episode, watched: Bool) async {
        guard session.isSignedIn else {
            session.promptSignIn()
            return
        }
        guard let source = selectedSource, let position = episode.position else { return }

        if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
            episodes[index].isWatched = watched
        }

        do {
            if watched {
                try await client.send(
                    EpisodeEndpoints.markWatched(releaseID: release.id, sourceID: source.id, position: position)
                )
            } else {
                try await client.send(
                    EpisodeEndpoints.markUnwatched(releaseID: release.id, sourceID: source.id, position: position)
                )
            }
        } catch {
            if let index = episodes.firstIndex(where: { $0.id == episode.id }) {
                episodes[index].isWatched = !watched
            }
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    /// The overflow's "отметить все": one call, then the list is refetched so the
    /// marks come from the server rather than from a guess.
    func markAllWatched() async {
        await markAll(watched: true)
    }

    func markAllUnwatched() async {
        await markAll(watched: false)
    }

    private func markAll(watched: Bool) async {
        guard session.isSignedIn else {
            session.promptSignIn()
            return
        }
        guard let source = selectedSource else { return }
        do {
            if watched {
                try await client.send(EpisodeEndpoints.markAllWatched(releaseID: release.id, sourceID: source.id))
            } else {
                try await client.send(EpisodeEndpoints.markAllUnwatched(releaseID: release.id, sourceID: source.id))
            }
            await loadEpisodes()
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    /// Stores playback progress so "continue watching" survives a reinstall.
    /// Best-effort: losing a position is not worth an error in the player.
    func saveProgress(for episode: Episode, seconds: TimeInterval) async {
        guard session.isSignedIn, let source = selectedSource, let position = episode.position else { return }
        _ = try? await client.send(
            EpisodeEndpoints.saveProgress(releaseID: release.id, sourceID: source.id, position: position)
        )
        _ = seconds
    }

    func nextEpisode(after episode: Episode) -> Episode? {
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }),
              episodes.indices.contains(index + 1)
        else { return nil }
        return episodes[index + 1]
    }
}
