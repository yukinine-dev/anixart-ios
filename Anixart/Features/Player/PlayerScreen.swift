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

    let episode: Episode
    let releaseTitle: String
    let preferences: PlaybackPreferences
    let onProgress: (TimeInterval) -> Void
    let onFinished: () -> Void

    /// Decided before this screen appears, by `EpisodeLauncher`.
    let choice: PlayerChoice
    /// What was found for this episode: the streams, and the page behind them.
    let target: PlaybackTarget

    var body: some View {
        Group {
            switch resolvedChoice {
            case .embedded:
                EmbeddedPlayerView(
                    variants: target.variants,
                    referer: target.referer,
                    streamSourceName: target.streamSourceName,
                    releaseTitle: releaseTitle,
                    episodeTitle: episode.displayName,
                    startAt: episode.resumePosition,
                    preferences: preferences,
                    onProgress: onProgress,
                    onFinished: onFinished
                )
            case .external:
                if let url = target.variants.first?.url {
                    ExternalHandoff(url: url) { dismiss() }
                } else {
                    unavailable
                }
            case .web:
                if let page = target.pageURL ?? target.variants.first?.url {
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

    /// The embedded and external players need a stream. Without one only the
    /// web player can show anything, whatever the user picked.
    private var resolvedChoice: PlayerChoice {
        target.supportsDirectPlayback ? choice : .web
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
