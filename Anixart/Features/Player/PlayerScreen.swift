import SwiftUI
import AVKit
import AVFoundation
import AnixartKit

/// Routes an episode to the right player.
///
/// Anixart serves two kinds of episode: a direct video URL, which `AVPlayer` can
/// play natively, and an `iframe` page belonging to a hosting (Kodik, Sibnet,
/// VK Video), which has to run in a web view because the real stream sits behind
/// that page's own player and token handling. `Episode.iframe` says which it is.
@MainActor
struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss

    let episode: Episode
    let releaseTitle: String
    let onProgress: (TimeInterval) -> Void
    let onFinished: () -> Void

    var body: some View {
        Group {
            if let url = episode.playbackURL {
                if episode.isEmbed {
                    EmbedPlayerView(url: url, title: episode.displayName)
                        .ignoresSafeArea()
                        .overlay(alignment: .topLeading) { closeButton }
                        // A hosting's own player reports nothing back, so the episode
                        // is marked watched on exit rather than at the end of the video.
                        .onDisappear { onFinished() }
                } else {
                    NativePlayerView(
                        url: url,
                        startAt: episode.resumePosition,
                        onProgress: onProgress,
                        onFinished: onFinished
                    )
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) { closeButton }
                }
            } else {
                unavailable
            }
        }
        .background(.black)
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

/// `AVPlayer` for direct video URLs, with resume and progress reporting.
@MainActor
struct NativePlayerView: View {
    let url: URL
    let startAt: TimeInterval?
    let onProgress: (TimeInterval) -> Void
    let onFinished: () -> Void

    @State private var player = AVPlayer()
    @State private var hasReportedFinish = false

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                if let startAt, startAt > 1 {
                    player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
                }
                player.play()
            }
            .onDisappear {
                report()
                player.pause()
            }
            // Polling on the main actor rather than through addPeriodicTimeObserver:
            // the loop is cancelled with the view, and nothing has to cross actors.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    report()
                }
            }
    }

    private func report() {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return }
        onProgress(seconds)

        // Treat 90% as finished, as most players do -- the credits are not the point.
        guard !hasReportedFinish,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0,
              seconds / duration > 0.9
        else { return }
        hasReportedFinish = true
        onFinished()
    }
}
