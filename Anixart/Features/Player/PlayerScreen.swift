import SwiftUI
import AVKit
import AVFoundation
import AnixartKit

/// Routes an episode to the player the user picked.
///
/// Anixart serves two kinds of episode. A direct video URL can go to any of the
/// three players. An `iframe` episode is a hosting's own player page (Kodik,
/// Sibnet, VK Video) whose real stream sits behind that page's own token
/// handling, so only the web player can show it -- which is why the Android app
/// keeps "Невозможно воспроизвести видео в выбранном плеере. Попробуйте
/// использовать Веб-плеер." in its strings. `Episode.iframe` says which it is.
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

    var body: some View {
        Group {
            if let url = episode.playbackURL {
                switch resolved(for: url) {
                case .embedded:
                    EmbeddedPlayerView(
                        url: url,
                        releaseTitle: releaseTitle,
                        episodeTitle: episode.displayName,
                        startAt: episode.resumePosition,
                        preferences: preferences,
                        onProgress: onProgress,
                        onFinished: onFinished
                    )
                case .external:
                    ExternalHandoff(url: url) { dismiss() }
                case .web:
                    EmbedPlayerView(url: url, title: episode.displayName)
                        .ignoresSafeArea()
                        .overlay(alignment: .topLeading) { closeButton }
                        // A hosting's own player reports nothing back, so the
                        // episode is marked watched on exit rather than at the
                        // end of the video.
                        .onDisappear { onFinished() }
                }
            } else {
                unavailable
            }
        }
        .background(.black)
    }

    /// The embedded and external players need a stream; an `iframe` episode only
    /// has a page, so those two fall back to the web player.
    private func resolved(for url: URL) -> PlayerChoice {
        episode.isEmbed ? .web : choice
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
