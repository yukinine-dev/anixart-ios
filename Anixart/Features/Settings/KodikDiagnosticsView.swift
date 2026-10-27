import SwiftUI
import AnixartKit

/// Shows what a Kodik page does on this device.
///
/// Four runs of this in a simulator reported nothing at all, and a simulator is
/// a poor instrument for it: no real device, a datacentre address, and a hosting
/// that may simply decline. A phone on an ordinary connection is the measurement
/// that counts, so this puts the same observation on a screen the user can open
/// and read.
///
/// Everything here is the real advert screen -- `KodikAdView` is what playback
/// will use -- with its findings printed instead of handed to a player.
@MainActor
struct KodikDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var env

    /// «Киберпанк: Бегущие по краю», whose 25 voice-overs are all on Kodik.
    private let releaseID = 18846

    @State private var episodeURL: URL?
    /// Named on screen, because "which release is this even?" was a fair
    /// question to have to ask.
    @State private var what = ""
    @State private var note = "Ищем серию на Kodik…"
    @State private var found: [URL] = []
    /// Which of them the picker chose as the episode, as opposed to the advert.
    @State private var stream: URL?
    @State private var diagnosis: KodikAdView.Diagnosis?
    @State private var isRunning = false
    /// What the server says about the Kodik path. Everything here comes from
    /// `config/toggles`, which is the only place the wrapper's address exists.
    @State private var wrapperBase: String?
    @State private var linksURL: String?
    @State private var iframeAd: Bool?

    var body: some View {
        List {
            Section("Конфиг сервера") {
                row("kodikIframeAd", iframeAd.map { $0 ? "да" : "нет" } ?? "—")
                VStack(alignment: .leading, spacing: 2) {
                    Text("kodikAdIframeUrl").font(.ax(.caption)).foregroundStyle(.secondary)
                    Text(wrapperBase ?? "— не пришёл").font(.ax(.caption)).monospaced()
                        .textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("kodikVideoLinksUrl").font(.ax(.caption)).foregroundStyle(.secondary)
                    Text(linksURL ?? "— не пришёл").font(.ax(.caption)).monospaced()
                        .textSelection(.enabled)
                }
            }

            Section {
                if !what.isEmpty {
                    Text(what).font(.ax(.subheadline))
                }
                if let episodeURL {
                    Text(episodeURL.absoluteString)
                        .font(.ax(.caption)).monospaced()
                        .textSelection(.enabled)
                } else {
                    Text(note).font(.ax(.subheadline)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Серия")
            }

            if isRunning {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Открываем страницу Kodik, ждём рекламу…")
                            .font(.ax(.subheadline))
                    }
                }
            }

            if let diagnosis {
                Section("Что увидела страница") {
                    row("Реклама отрапортовала", diagnosis.advertFinished ? "да" : "нет")
                    row("Живых фреймов", "\(diagnosis.frames.count)")
                    row("Запросов", "\(diagnosis.requests.count)")
                    row("Ссылок на видео", "\(found.count)")
                    row("Поток серии", stream == nil ? "не найден" : "найден")
                }

                if !diagnosis.frames.isEmpty {
                    Section("Фреймы") {
                        ForEach(diagnosis.frames, id: \.self) { frame in
                            Text(frame).font(.ax(.caption)).monospaced().lineLimit(2)
                        }
                    }
                }

                if !diagnosis.requests.isEmpty {
                    Section("Запросы") {
                        ForEach(diagnosis.requests, id: \.self) { request in
                            Text(request).font(.ax(.caption)).monospaced().lineLimit(3)
                        }
                    }
                }

                if !found.isEmpty {
                    Section("Найденное видео") {
                        ForEach(found, id: \.self) { url in
                            Text(url.absoluteString)
                                .font(.ax(.caption)).monospaced()
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        UIPasteboard.general.string = summary
                    } label: {
                        Label("Скопировать отчёт", systemImage: "doc.on.doc")
                    }
                } footer: {
                    Text("Скопируйте и пришлите — по этому отчёту пишется извлечение потока.")
                }
            }

            // The page is loaded off-screen on purpose: this is a measurement,
            // not a viewing. Its advert still plays, which is the point.
            if let episodeURL, isRunning {
                Section {
                    KodikAdView(
                        url: episodeURL,
                        onResolved: { media, result in
                            found = media.map(\.url)
                            stream = KodikAdView.episodeStream(from: media)
                            diagnosis = result
                            isRunning = false
                        },
                        onFailure: { reason in
                            note = "Страница не загрузилась: \(reason)"
                            diagnosis = KodikAdView.Diagnosis()
                            isRunning = false
                        }
                    )
                    .frame(height: 200)
                }
            }
        }
        .navigationTitle("Диагностика Kodik")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard episodeURL == nil else { return }
            await findEpisode()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.ax(.subheadline))
            Spacer()
            Text(value).font(.ax(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var summary: String {
        var lines = [
            what,
            "kodikIframeAd: \(iframeAd.map(String.init(describing:)) ?? "nil")",
            "kodikAdIframeUrl: \(wrapperBase ?? "nil")",
            "kodikVideoLinksUrl: \(linksURL ?? "nil")",
            "kodik: \(episodeURL?.absoluteString ?? "—")"
        ]
        if let diagnosis {
            lines.append("advert finished: \(diagnosis.advertFinished)")
            lines.append("frames: \(diagnosis.frames.count)")
            lines += diagnosis.frames.map { "  frame \($0)" }
            lines.append("requests: \(diagnosis.requests.count)")
            lines += diagnosis.requests.map { "  \($0)" }
            lines.append("stream: \(stream?.absoluteString ?? "—")")
            lines.append("media: \(found.count)")
            lines += found.map { "  \($0.absoluteString)" }
        }
        return lines.joined(separator: "\n")
    }

    private func findEpisode() async {
        let client = env.client

        // The wrapper's address is server-side only, so it has to be read before
        // anything can be opened.
        let toggles = env.session.toggles
        wrapperBase = toggles?.kodikAdIframeUrl
        linksURL = toggles?.kodikVideoLinksUrl
        iframeAd = toggles?.kodikIframeAd
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

                guard let url = episodes.lazy.compactMap(\.playbackURL).first(where: {
                    let host = $0.host() ?? ""
                    return host.contains("kodik") || host.contains("aniqit")
                }) else { continue }

                // The wrapper when the server named one; the bare URL otherwise,
                // so the report shows what each does.
                episodeURL = KodikWrapper.url(for: url, base: wrapperBase) ?? url
                what = "«Киберпанк: Бегущие по краю» · \(type.displayName) / \(source.displayName)"
                    + (wrapperBase == nil ? " · без обёртки" : " · через обёртку")
                isRunning = true
                return
            }
        }
        note = "Ни одной серии на Kodik не нашлось"
    }
}
