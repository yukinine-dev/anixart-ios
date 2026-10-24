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

    private(set) var selectedType: EpisodeType?
    private(set) var selectedSource: EpisodeSource?

    private(set) var isLoadingTypes = false
    private(set) var isLoadingEpisodes = false
    private(set) var errorMessage: String?

    /// `0` ascending, `1` descending -- the `sort` query on the episodes endpoint.
    /// Changed through `toggleSortOrder()`, since `@Observable` does not track a
    /// stored property that declares a `didSet`.
    private(set) var sortDescending = false

    private let release: Release
    private let client: AnixartClient
    private let session: SessionController

    init(release: Release, client: AnixartClient, session: SessionController) {
        self.release = release
        self.client = client
        self.session = session
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
            if let first = types.first {
                await select(type: first)
            }
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
        isLoadingTypes = false
    }

    func toggleSortOrder() async {
        sortDescending.toggle()
        await loadEpisodes()
    }

    func select(type: EpisodeType) async {
        selectedType = type
        sources = []
        episodes = []
        selectedSource = nil
        do {
            let response = try await client.send(
                EpisodeEndpoints.sources(releaseID: release.id, typeID: type.id)
            )
            sources = response.sources ?? []
            if let first = sources.first {
                await select(source: first)
            }
        } catch {
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    func select(source: EpisodeSource) async {
        selectedSource = source
        await loadEpisodes()
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
