import SwiftUI
import AVKit
import AVFoundation
import AnixartKit

/// Routes an episode to the player the user picked.
///
/// Anixart never serves the video itself: every hosting it lists answers with
/// its own player page, which is why the Android app keeps "Невозможно
/// воспроизвести видео в выбранном плеере. Попробуйте использовать Веб-плеер."
/// in its strings. So the stream, when there is one, comes from the hosting's
/// own public API -- `PlaybackResolver` works that out before this appears, and
/// hands the result over as a `PlaybackTarget`.
@MainActor
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    let episode: Episode
    let releaseTitle: String
    let preferences: PlaybackPreferences
    let onProgress: (TimeInterval) -> Void
    let onFinished: () -> Void

    /// Decided before this screen appears, by `EpisodeLauncher`.
    let choice: PlayerChoice
    /// What was found for this episode: the streams, and the page behind them.
    let target: PlaybackTarget

    /// What the Kodik advert screen handed over, once it has.
    @State private var kodikStream: StreamVariant?
    /// Set when the advert screen came back with nothing, so the web player can
    /// take over rather than leaving a blank screen.
    @State private var kodikGaveUp = false
    @State private var prefersWebFallback = false

    var body: some View {
        Group {
            switch resolvedChoice {
            case .kodik:
                kodikGate
            case .embedded:
                EmbeddedPlayerView(
                    variants: kodikStream.map { [$0] } ?? target.variants,
                    referer: kodikStream == nil ? target.referer : KodikWrapper.referer,
                    streamSourceName: kodikStream == nil ? target.streamSourceName : "Kodik",
                    releaseTitle: releaseTitle,
                    episodeTitle: episode.displayName,
                    startAt: episode.resumePosition,
                    preferences: preferences,
                    onProgress: onProgress,
                    onFinished: onFinished,
                    onWebFallback: webFallbackAction
                )
            case .external:
                if let url = target.variants.first?.url {
                    ExternalHandoff(url: url) { dismiss() }
                } else {
                    unavailable
                }
            case .web:
                // Never the advert wrapper once the gate has already shown one:
                // falling back into it played a second advert, which is what
                // made it feel endless.
                if let page = webPage(withAdvert: Self.shouldUseWebAdvert(
                    kodikGaveUp: kodikGaveUp, hasKodikStream: kodikStream != nil
                )) {
                    EmbedPlayerView(url: page, title: episode.displayName)
                        .ignoresSafeArea()
                        .overlay(alignment: .topLeading) { closeButton }
                        // A hosting's own player reports nothing back, so the
                        // episode is marked watched on exit rather than at the
                        // end of the video.
                        .onDisappear { onFinished() }
                } else {
                    unavailable
                }
            }
        }
        .background(.black)
    }

    /// Keep the hosting URL separate from the wrapper loaded by the web player.
    private var hostingURL: URL? {
        target.pageURL ?? target.variants.first?.url
    }

    private var webFallbackAction: (() -> Void)? {
        guard hostingURL != nil else { return nil }
        return { prefersWebFallback = true }
    }

    static func shouldUseWebAdvert(kodikGaveUp: Bool, hasKodikStream: Bool) -> Bool {
        !kodikGaveUp && !hasKodikStream
    }

    /// The embedded and external players need a stream. Without one only the
    /// web player can show anything -- except on Kodik, where the stream exists
    /// but only the page knows it, and the advert has to be watched first.
    enum Route: Equatable {
        case embedded, external, web, kodik

        static func resolve(
            choice: PlayerChoice,
            supportsDirectPlayback: Bool,
            hostingURL: URL?,
            hasKodikStream: Bool,
            kodikGaveUp: Bool,
            prefersWebFallback: Bool
        ) -> Route {
            if prefersWebFallback { return .web }
            if hasKodikStream { return .embedded }
            if supportsDirectPlayback {
                switch choice {
                case .embedded: return .embedded
                case .external: return .external
                case .web: return .web
                }
            }
            if choice == .embedded, !kodikGaveUp,
               let hostingURL, KodikWrapper.handles(hostingURL) { return .kodik }
            return .web
        }
    }

    var resolvedChoice: Route {
        Route.resolve(
            choice: choice,
            supportsDirectPlayback: target.supportsDirectPlayback,
            hostingURL: hostingURL,
            hasKodikStream: kodikStream != nil,
            kodikGaveUp: kodikGaveUp,
            prefersWebFallback: prefersWebFallback
        )
    }

    /// The advert, then the episode in the built-in player.
    ///
    /// The page runs for real -- the advert plays, and Kodik's own callback is
    /// what says when it is over. Nothing here goes around it; the stream is
    /// read from what the page itself then loads.
    @ViewBuilder
    private var kodikGate: some View {
        if let page = webPage() {
            ZStack {
                KodikAdView(
                    url: page,
                    onResolved: { media, _ in
                        if let url = KodikAdView.episodeStream(from: media) {
                            kodikStream = StreamVariant(url: url)
                        } else {
                            kodikGaveUp = true
                        }
                    },
                    onFailure: { _ in kodikGaveUp = true }
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    Spacer()
                    Text("Реклама источника. Серия откроется во встроенном плеере.")
                        .font(.ax(.caption))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // A waterfall of ad networks can take a while before one
                    // fills, and nobody should be held in it with no way out.
                    // This leaves for the source's own player -- it does not
                    // skip anyone's advert.
                    Button("Открыть плеер источника") {
                        kodikGaveUp = true
                    }
                    .font(.ax(.subheadline, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18), in: Capsule())
                    .padding(.bottom, 32)
                }
            }
            .overlay(alignment: .topLeading) { closeButton }
        } else {
            unavailable
        }
    }

    /// What the web player opens.
    ///
    /// A hosting's page is not meant to be loaded directly -- Kodik answers
    /// "данной страницы не существует" to one -- so it goes through the wrapper
    /// the server names, which is what the Android client loads. With the advert
    /// wrapper when the server asks for it, the plain one otherwise.
    private func webPage(withAdvert: Bool = true) -> URL? {
        guard let page = hostingURL else { return nil }
        guard KodikWrapper.handles(page) else { return page }

        let toggles = env.session.toggles
        let base = (withAdvert && (toggles?.kodikIframeAd ?? false))
            ? toggles?.kodikAdIframeUrl
            : toggles?.iframeEmbedUrl
        return KodikWrapper.url(for: page, base: base) ?? page
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.ax(.headline))
                .foregroundStyle(.white)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
        }
        .padding()
    }

    private var unavailable: some View {
        VStack(spacing: 16) {
            StatusMessageView(
                title: "Серия недоступна",
                message: "Источник не вернул ссылку на видео",
                systemImage: "exclamationmark.triangle"
            )
            Button("Закрыть") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// "Сторонний плеер": hands the stream to whatever is installed and closes.
@MainActor
struct ExternalHandoff: View {
    @Environment(\.openURL) private var openURL

    let url: URL
    let onDone: () -> Void

    @State private var didOpen = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            if failed {
                StatusMessageView(
                    title: "Сторонний плеер не найден",
                    message: "Установите плеер, который открывает видео по ссылке, или выберите другой вариант",
                    systemImage: "square.and.arrow.up"
                )
            } else {
                ProgressView().tint(.white)
            }
            Button("Закрыть") { onDone() }
                .buttonStyle(.bordered)
        }
        .task {
            guard !didOpen else { return }
            didOpen = true
            openURL(url) { accepted in
                if accepted {
                    onDone()
                } else {
                    failed = true
                }
            }
        }
    }
}
