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
    private let session: SessionController
    let viewer: ProfileViewerKey
    private var typesGeneration = 0
    private var selectionGeneration = 0
    private var episodesGeneration = 0
    @ObservationIgnored private var playabilityTask: Task<Void, Never>?
    private struct WatchKey: Hashable { let sourceID: Int; let position: Int }
    private struct WatchUpdate { let revision: Int; let watched: Bool? }
    private var watchRevision = 0
    private var watchUpdates: [WatchKey: WatchUpdate] = [:]
    private var sourceCacheRevisions: [Int: Int] = [:]
    private var pendingWatchKeys = Set<WatchKey>()
    private var markingAllSources = Set<Int>()

    init(release: Release, session: SessionController, viewer: ProfileViewerKey? = nil) {
        self.release = release
        self.session = session
        self.viewer = viewer ?? session.viewerKey
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var isUpdatingWatched: Bool { !pendingWatchKeys.isEmpty || !markingAllSources.isEmpty }

    func invalidate() {
        typesGeneration += 1
        selectionGeneration += 1
        episodesGeneration += 1
        playabilityTask?.cancel()
        playabilityTask = nil
        types = []
        sources = []
        episodes = []
        episodesBySource = [:]
        watchUpdates = [:]
        sourceCacheRevisions = [:]
        selectedType = nil
        selectedSource = nil
        playableTypeIDs = []
        playableSourceIDs = []
        hostingGivesStream = [:]
        isLoadingTypes = false
        isLoadingEpisodes = false
        isCheckingPlayability = false
        errorMessage = nil
    }

    /// Voice-overs known to have a hosting the built-in player can take.
    ///
    /// Filled in the background after the list appears: the user should not wait
    /// on it, and the list is useful without it.
    private(set) var playableTypeIDs: Set<Int> = []
    private(set) var isCheckingPlayability = false

    /// Whether a hosting can be played is a property of the hosting, not of the
    /// release, so each one is classified once per screen by name instead of
    /// fetching every voice-over's episodes.
    ///
    /// "Can be played" means a stream was found for it: either the hosting
    /// really handed over a video, or a source with its own public API has the
    /// same episode. On this API it is always the second.
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
        guard hasCurrentViewer else { return }
        self.kind = kind
    }

    /// Re-fetches the voice-over list, for the toolbar's refresh.
    func reload() async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        typesGeneration += 1
        playabilityTask?.cancel()
        isCheckingPlayability = false
        isLoadingTypes = false
        types = []
        playableTypeIDs = []
        await loadTypes()
    }

    var releaseID: Int { release.id }
    var releaseTitle: String { release.displayTitle }

    func loadTypes() async {
        guard hasCurrentViewer, !Task.isCancelled, types.isEmpty, !isLoadingTypes else { return }
        typesGeneration += 1
        let generation = typesGeneration
        isLoadingTypes = true
        errorMessage = nil
        defer { if generation == typesGeneration { isLoadingTypes = false } }
        do {
            let response = try await session.sendViewerRequest(EpisodeEndpoints.types(releaseID: release.id), for: viewer)
            guard generation == typesGeneration, hasCurrentViewer, !Task.isCancelled else { return }
            types = response.types ?? []
            // Pinned voice-overs come first in the Android UI; everything else keeps
            // the order the server sent.
            types.sort { lhs, rhs in
                let lhsPinned = lhs.pinned ?? false
                let rhsPinned = rhs.pinned ?? false
                return lhsPinned && !rhsPinned
            }
        } catch {
            if generation == typesGeneration { showError(error) }
            return
        }
        playabilityTask?.cancel()
        playabilityTask = Task { await checkPlayability(generation: generation) }
    }

    /// Works out which voice-overs the built-in player can handle.
    ///
    /// Sources are cheap to list, so every voice-over's are fetched; episodes
    /// are not, so one episode list per distinct hosting is enough to classify
    /// it. Results land as they arrive, so badges appear progressively.
    private func checkPlayability(generation: Int) async {
        guard hasCurrentViewer, generation == typesGeneration, !Task.isCancelled, !isCheckingPlayability else { return }
        isCheckingPlayability = true
        defer { if generation == typesGeneration { isCheckingPlayability = false } }

        let session = self.session
        let viewer = self.viewer
        let releaseID = release.id
        let allTypes = types

        let sourcesByType = await withTaskGroup(of: (Int, [EpisodeSource]).self) { group in
            for type in allTypes {
                group.addTask {
                    let response = try? await session.sendViewerRequest(
                        EpisodeEndpoints.sources(releaseID: releaseID, typeID: type.id), for: viewer
                    )
                    return (type.id, response?.sources ?? [])
                }
            }
            var result: [Int: [EpisodeSource]] = [:]
            for await (id, sources) in group { result[id] = sources }
            return result
        }
        guard hasCurrentViewer, generation == typesGeneration, !Task.isCancelled else { return }

        for (typeID, sources) in sourcesByType {
            for source in sources {
                guard hasCurrentViewer, generation == typesGeneration, !Task.isCancelled else { return }
                let name = source.displayName
                if hostingGivesStream[name] == nil {
                    let response = try? await session.sendViewerRequest(
                        EpisodeEndpoints.episodes(
                            releaseID: releaseID,
                            typeID: typeID,
                            sourceID: source.id,
                            sort: 0
                        ), for: viewer
                    )
                    guard let episode = response?.episodes?.first(where: { $0.playbackURL != nil })
                    else { continue }
                    let target = await PlaybackResolver.shared.target(for: episode)
                    guard hasCurrentViewer, generation == typesGeneration, !Task.isCancelled else { return }
                    hostingGivesStream[name] = target.supportsDirectPlayback
                }
                if hostingGivesStream[name] == true {
                    playableTypeIDs.insert(typeID)
                    break
                }
            }
        }
    }

    func toggleSortOrder() async {
        guard hasCurrentViewer else { return }
        sortDescending.toggle()
        // Order is just the position, so the cached list is re-sorted rather
        // than refetched.
        episodes = sorted(episodes)
    }

    func select(type: EpisodeType) async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        selectionGeneration += 1
        episodesGeneration += 1
        let generation = selectionGeneration
        let sourceGeneration = episodesGeneration
        selectedType = type
        sources = []
        episodes = []
        selectedSource = nil
        episodesBySource = [:]
        watchUpdates = [:]
        sourceCacheRevisions = [:]
        playableSourceIDs = []
        isLoadingEpisodes = true
        errorMessage = nil
        defer {
            if generation == selectionGeneration, sourceGeneration == episodesGeneration { isLoadingEpisodes = false }
        }
        do {
            let response = try await session.sendViewerRequest(
                EpisodeEndpoints.sources(releaseID: release.id, typeID: type.id), for: viewer
            )
            guard isCurrentSelection(generation, typeID: type.id) else { return }
            let loaded = response.sources ?? []
            sources = loaded
            await loadEverySource(type: type, sources: loaded, generation: generation)
            guard isCurrentSelection(generation, typeID: type.id) else { return }
            await probeSources(loaded, typeID: type.id, generation: generation)
            guard isCurrentSelection(generation, typeID: type.id) else { return }

            // Prefer a hosting the built-in player can actually open, when one
            // exists at all.
            let preferred = loaded.first(where: hasDirectStream) ?? loaded.first
            // The source chips are already interactive while prefetching. Do not
            // replace an explicit choice with the automatically preferred source.
            if selectedSource == nil, let preferred { await select(source: preferred) }
        } catch {
            if isCurrentSelection(generation, typeID: type.id) { showError(error) }
        }
    }

    func select(source: EpisodeSource) async {
        guard hasCurrentViewer, !Task.isCancelled, sources.contains(where: { $0.id == source.id }) else { return }
        episodesGeneration += 1
        selectedSource = source
        errorMessage = nil
        if let cached = episodesBySource[source.id] {
            episodes = sorted(cached)
            isLoadingEpisodes = false
        } else {
            episodes = []
            await loadEpisodes()
        }
    }

    /// Hostings a stream was actually found for.
    ///
    /// Established by resolving one of their episodes, not by reading
    /// `Episode.iframe`: that flag does not mean what it looks like -- Libria's
    /// "non-iframe" URL is an HTML player page, and the stream behind it comes
    /// from AniLibria's own API.
    private(set) var playableSourceIDs: Set<Int> = []

    func hasDirectStream(_ source: EpisodeSource) -> Bool {
        playableSourceIDs.contains(source.id)
    }

    /// The hosting to point the user at when the current one is a page only.
    var sourceWithDirectStream: EpisodeSource? {
        sources.first(where: hasDirectStream)
    }

    private func loadEverySource(type: EpisodeType, sources: [EpisodeSource], generation: Int) async {
        let session = self.session
        let viewer = self.viewer
        let releaseID = release.id
        let sortDescending = self.sortDescending
        let watchRevision = self.watchRevision
        let cacheRevisions = sourceCacheRevisions

        let loaded = await withTaskGroup(of: (Int, [Episode]?).self) { group in
            for source in sources {
                group.addTask {
                    let response = try? await session.sendViewerRequest(
                        EpisodeEndpoints.episodes(
                            releaseID: releaseID,
                            typeID: type.id,
                            sourceID: source.id,
                            sort: sortDescending ? 1 : 0
                        ), for: viewer
                    )
                    // A failed prefetch is not an empty episode list. Leaving it
                    // uncached allows selecting that source to retry the request.
                    return (source.id, response.map {
                        Self.contextualEpisodes($0.episodes ?? [], releaseID: releaseID, sourceID: source.id)
                    })
                }
            }
            var result: [Int: [Episode]] = [:]
            for await (id, episodes) in group {
                if let episodes { result[id] = episodes }
            }
            return result
        }
        guard isCurrentSelection(generation, typeID: type.id) else { return }
        // A direct source load or watch action may already have updated its
        // cache while the prefetch was in flight. Keep that newer copy.
        for (id, episodes) in loaded where episodesBySource[id] == nil
            && sourceCacheRevisions[id, default: 0] == cacheRevisions[id, default: 0] {
            episodesBySource[id] = applyingWatchUpdates(to: episodes, sourceID: id, since: watchRevision)
        }
    }

    /// Works out which hostings a stream can be found for, by resolving one
    /// episode of each.
    private func probeSources(_ sources: [EpisodeSource], typeID: Int, generation: Int) async {
        var playable: Set<Int> = []
        for source in sources {
            guard isCurrentSelection(generation, typeID: typeID) else { return }
            guard let episode = episodesBySource[source.id]?.first(where: { $0.playbackURL != nil })
            else { continue }
            let target = await PlaybackResolver.shared.target(for: episode)
            guard isCurrentSelection(generation, typeID: typeID) else { return }
            if target.supportsDirectPlayback { playable.insert(source.id) }
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
        guard hasCurrentViewer, !Task.isCancelled, let type = selectedType, let source = selectedSource else { return }
        episodesGeneration += 1
        let generation = episodesGeneration
        let selection = selectionGeneration
        let watchRevision = self.watchRevision
        isLoadingEpisodes = true
        errorMessage = nil
        defer { if generation == episodesGeneration { isLoadingEpisodes = false } }
        do {
            let response = try await session.sendViewerRequest(
                EpisodeEndpoints.episodes(
                    releaseID: release.id,
                    typeID: type.id,
                    sourceID: source.id,
                    sort: sortDescending ? 1 : 0
                ), for: viewer
            )
            guard generation == episodesGeneration, isCurrentSelection(selection, typeID: type.id), selectedSource?.id == source.id else { return }
            let loaded = Self.contextualEpisodes(response.episodes ?? [], releaseID: release.id, sourceID: source.id)
            episodes = sorted(applyingWatchUpdates(to: loaded, sourceID: source.id, since: watchRevision))
            episodesBySource[source.id] = episodes
        } catch {
            guard generation == episodesGeneration, isCurrentSelection(selection, typeID: type.id), selectedSource?.id == source.id,
                  !ProfileRequestFailure.isCancellation(error) else { return }
            episodes = []
            showError(error)
        }
    }

    /// Marks an episode watched and flips it locally so the checkmark appears at once.
    func markWatched(_ episode: Episode, watched: Bool) async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        guard let account = viewer.account else {
            session.promptSignIn()
            return
        }
        guard let sourceID = episode.sourceId ?? selectedSource?.id, sourceID > 0, let position = episode.position,
              episode.releaseId == nil || episode.releaseId == release.id else { return }
        let key = WatchKey(sourceID: sourceID, position: position)
        guard !pendingWatchKeys.contains(key), !markingAllSources.contains(sourceID) else { return }
        pendingWatchKeys.insert(key)
        defer { pendingWatchKeys.remove(key) }
        let selection = selectionGeneration
        let previous = episodesBySource[sourceID]?.first(where: { $0.id == episode.id })?.isWatched ?? episode.isWatched

        recordWatch(episodeID: episode.id, key: key, watched: watched)

        do {
            if watched {
                try await session.sendConfirmedAccountRequest(
                    EpisodeEndpoints.markWatched(releaseID: release.id, sourceID: sourceID, position: position), for: account
                )
            } else {
                try await session.sendConfirmedAccountRequest(
                    EpisodeEndpoints.markUnwatched(releaseID: release.id, sourceID: sourceID, position: position), for: account
                )
            }
            if selection == selectionGeneration {
                // A list request started during the mutation may still contain
                // the old mark, even if it arrives after this acknowledgement.
                recordWatch(episodeID: episode.id, key: key, watched: watched)
            }
            await session.refreshProfile(for: account)
        } catch {
            guard hasCurrentViewer else { return }
            if selection == selectionGeneration {
                recordWatch(episodeID: episode.id, key: key, watched: previous)
                if selectedSource?.id == sourceID { showError(error) }
            }
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
        guard hasCurrentViewer, !Task.isCancelled else { return }
        guard let account = viewer.account else {
            session.promptSignIn()
            return
        }
        guard let source = selectedSource else { return }
        guard !markingAllSources.contains(source.id), !pendingWatchKeys.contains(where: { $0.sourceID == source.id }) else { return }
        markingAllSources.insert(source.id)
        defer { markingAllSources.remove(source.id) }
        let selection = selectionGeneration
        do {
            if watched {
                try await session.sendConfirmedAccountRequest(EpisodeEndpoints.markAllWatched(releaseID: release.id, sourceID: source.id), for: account)
            } else {
                try await session.sendConfirmedAccountRequest(EpisodeEndpoints.markAllUnwatched(releaseID: release.id, sourceID: source.id), for: account)
            }
            if selection == selectionGeneration {
                // Do not let a prefetch started before this bulk mutation
                // repopulate the invalidated hosting with its old marks.
                sourceCacheRevisions[source.id, default: 0] += 1
                episodesBySource[source.id] = nil
                if selectedSource?.id == source.id { await loadEpisodes() }
            }
            await session.refreshProfile(for: account)
        } catch {
            if selection == selectionGeneration, selectedSource?.id == source.id { showError(error) }
        }
    }

    /// Stores playback progress so "continue watching" survives a reinstall.
    /// Best-effort: losing a position is not worth an error in the player.
    func saveProgress(for episode: Episode, seconds: TimeInterval) async {
        guard hasCurrentViewer, let account = viewer.account, let sourceID = episode.sourceId ?? selectedSource?.id, sourceID > 0,
              let position = episode.position, episode.releaseId == nil || episode.releaseId == release.id else { return }
        _ = try? await session.sendConfirmedAccountRequest(
            EpisodeEndpoints.saveProgress(releaseID: release.id, sourceID: sourceID, position: position), for: account
        )
        _ = seconds
    }

    func nextEpisode(after episode: Episode) -> Episode? {
        guard hasCurrentViewer, episode.releaseId == nil || episode.releaseId == release.id,
              let sourceID = episode.sourceId ?? selectedSource?.id else { return nil }
        let available = selectedSource?.id == sourceID ? episodes : sorted(episodesBySource[sourceID] ?? [])
        guard let index = available.firstIndex(where: { $0.id == episode.id }),
              available.indices.contains(index + 1)
        else { return nil }
        return available[index + 1]
    }

    private func isCurrentSelection(_ generation: Int, typeID: Int) -> Bool {
        hasCurrentViewer && !Task.isCancelled && generation == selectionGeneration && selectedType?.id == typeID
    }

    private func recordWatch(episodeID: Int, key: WatchKey, watched: Bool?) {
        watchRevision += 1
        watchUpdates[key] = WatchUpdate(revision: watchRevision, watched: watched)
        let sourceID = key.sourceID
        if var cached = episodesBySource[sourceID], let index = cached.firstIndex(where: { $0.id == episodeID }) {
            cached[index].isWatched = watched
            episodesBySource[sourceID] = cached
        }
        if selectedSource?.id == sourceID, let index = episodes.firstIndex(where: { $0.id == episodeID }) {
            episodes[index].isWatched = watched
        }
    }

    private func applyingWatchUpdates(to episodes: [Episode], sourceID: Int, since revision: Int) -> [Episode] {
        episodes.map { episode in
            guard let position = episode.position else { return episode }
            let key = WatchKey(sourceID: sourceID, position: position)
            guard let update = watchUpdates[key], update.revision > revision || pendingWatchKeys.contains(key) else { return episode }
            var updated = episode
            updated.isWatched = update.watched
            return updated
        }
    }

    /// Playback callbacks keep the hosting they were opened from, even if the
    /// picker changes hosting before a progress/watch response returns.
    nonisolated private static func contextualEpisodes(_ episodes: [Episode], releaseID: Int, sourceID: Int) -> [Episode] {
        episodes.map { episode in
            var contextual = episode
            if contextual.releaseId == nil { contextual.releaseId = releaseID }
            if contextual.sourceId == nil { contextual.sourceId = sourceID }
            return contextual
        }
    }

    private func showError(_ error: any Error) {
        guard hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) else { return }
        errorMessage = Paginator<Release>.message(for: error)
    }
}
