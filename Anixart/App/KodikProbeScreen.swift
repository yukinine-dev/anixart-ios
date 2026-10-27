import SwiftUI
import AnixartKit
import os

/// Loads a real Kodik episode through `KodikAdView` and logs what the page
/// played.
///
/// Reached only through `-anixart-screen kodik`. The stream URL is not in the
/// page's HTML, so it cannot be measured from outside a browser -- and the only
/// browser that matters here is the one the app ships. This runs that browser in
/// the smoke job and prints the answer, which is what the extraction then gets
/// written against.
@MainActor
struct KodikProbeScreen: View {
    private static let log = Logger(subsystem: "app.anixart.client", category: "smoke")

    @Environment(AppEnvironment.self) private var env

    /// «Киберпанк: Бегущие по краю», whose 25 voice-overs are all on Kodik.
    let releaseID: Int

    @State private var episodeURL: URL?
    @State private var status = "Ищем серию на Kodik…"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let episodeURL {
                KodikAdView(
                    url: episodeURL,
                    onResolved: { urls, result in
                        report("фреймов \(result.frames.count), запросов \(result.requests.count), "
                               + "реклама \(result.advertFinished ? "да" : "нет"), ссылок \(urls.count)")
                        for frame in result.frames.prefix(6) {
                            Self.log.notice("smoke kodik frame: \(frame, privacy: .public)")
                        }
                        for request in result.requests.prefix(10) {
                            Self.log.notice("smoke kodik request: \(request, privacy: .public)")
                        }
                        for url in urls.prefix(8) {
                            Self.log.notice("smoke kodik url: \(url.absoluteString, privacy: .public)")
                        }
                    },
                    onFailure: { reason in report("страница не загрузилась: \(reason)") }
                )
                .ignoresSafeArea()
            }

            VStack {
                Spacer()
                Text(status)
                    .font(.ax(.caption))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.bottom, 40)
            }
        }
        .task {
            guard episodeURL == nil else { return }
            await findEpisode()
        }
    }

    private func findEpisode() async {
        let client = env.client
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

                guard let episode = episodes.first(where: {
                    ($0.playbackURL?.host() ?? "").contains("kodik")
                        || ($0.playbackURL?.host() ?? "").contains("aniqit")
                }), let url = episode.playbackURL
                else { continue }

                episodeURL = url
                report("\(type.displayName) / \(source.displayName): \(url.absoluteString)")
                return
            }
        }
        report("ни одной серии на Kodik не нашлось")
    }

    private func report(_ message: String) {
        status = message
        // The workflow greps for this line.
        Self.log.notice("smoke kodik: \(message, privacy: .public)")
    }
}
