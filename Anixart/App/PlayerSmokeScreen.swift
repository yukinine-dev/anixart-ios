import SwiftUI
import AnixartKit
import os

/// Resolves a real episode and opens the built-in player on it.
///
/// Reached only through `-anixart-screen player`. Everything else about playback
/// has been checked by compiling it, which says nothing about whether a stream
/// is found or whether AVPlayer can open it. This walks a release's voice-overs
/// for a hosting a stream can be found for, logs what it found, and then shows
/// the player -- so the smoke test's screenshot carries real video and its log
/// carries the verdict.
@MainActor
struct PlayerSmokeScreen: View {
    private static let log = Logger(subsystem: "app.anixart.client", category: "smoke")

    @Environment(AppEnvironment.self) private var env

    /// Defaults to «Киберпанк: Бегущие по краю», which lists an AniLibria
    /// hosting -- the one case the bridge is known to cover.
    let releaseID: Int

    @State private var preferences = PlaybackPreferences()
    @State private var verdict = "Ищем серию…"
    @State private var episode: Episode?
    @State private var target: PlaybackTarget?
    @State private var releaseTitle = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let episode, let target, target.supportsDirectPlayback {
                EmbeddedPlayerView(
                    variants: target.variants,
                    referer: target.referer,
                    streamSourceName: target.streamSourceName,
                    releaseTitle: releaseTitle,
                    episodeTitle: episode.displayName,
                    startAt: nil,
                    preferences: preferences,
                    onProgress: { _ in },
                    onFinished: {}
                )
            }

            // Over the player, so the screenshot says what it is showing.
            VStack {
                Spacer()
                Text(verdict)
                    .font(.ax(.caption))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
        .task {
            guard episode == nil else { return }
            await resolve()
        }
    }

    private func resolve() async {
        let client = env.client

        guard let release = try? await client.send(ReleaseEndpoints.release(id: releaseID, extended: true)).release else {
            report("релиз \(releaseID) не загрузился")
            return
        }
        releaseTitle = release.displayTitle

        let types = (try? await client.send(EpisodeEndpoints.types(releaseID: releaseID)))?.types ?? []
        for type in types {
            let sources = (try? await client.send(
                EpisodeEndpoints.sources(releaseID: releaseID, typeID: type.id)
            ))?.sources ?? []

            for source in sources {
                let episodes = (try? await client.send(EpisodeEndpoints.episodes(
                    releaseID: releaseID,
                    typeID: type.id,
                    sourceID: source.id,
                    sort: 0
                )))?.episodes ?? []

                guard let candidate = episodes.first(where: { $0.playbackURL != nil }) else { continue }
                let resolved = await PlaybackResolver.shared.target(for: candidate)
                guard resolved.supportsDirectPlayback else { continue }

                episode = candidate
                target = resolved
                let rungs = resolved.variants.map(\.label).joined(separator: "/")
                report("\(release.displayTitle) · \(type.displayName) / \(source.displayName)"
                       + " · \(resolved.streamSourceName ?? "источник") · \(rungs)",
                       stream: true)
                return
            }
        }

        report("\(release.displayTitle): ни один хостинг не отдал видео")
    }

    private func report(_ message: String, stream: Bool = false) {
        verdict = message
        // The workflow greps for this line; `stream=` is the part that says
        // whether anything playable was found.
        Self.log.notice("smoke player: stream=\(stream ? "yes" : "no", privacy: .public) \(message, privacy: .public)")
    }
}
