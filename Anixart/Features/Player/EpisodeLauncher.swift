import SwiftUI
import AnixartKit

/// The sequence the Android app runs before an episode opens: the warning about
/// third-party sources, then "Выберите плеер" when the user has not told it to
/// stop asking, then the player itself.
@MainActor
@Observable
final class EpisodeLauncher {
    enum Stage: Equatable {
        case idle
        case warning(Episode)
        case picking(Episode)
        case playing(Episode, PlayerChoice)
    }

    private(set) var stage: Stage = .idle
    let preferences: PlaybackPreferences

    init(preferences: PlaybackPreferences) {
        self.preferences = preferences
    }

    var pendingEpisode: Episode? {
        switch stage {
        case .warning(let episode), .picking(let episode): return episode
        case .playing(let episode, _): return episode
        case .idle: return nil
        }
    }

    func open(_ episode: Episode) {
        stage = preferences.hasAcceptedDisclaimer ? next(after: episode) : .warning(episode)
    }

    func acceptWarning() {
        guard case .warning(let episode) = stage else { return }
        preferences.acceptDisclaimer()
        stage = next(after: episode)
    }

    func choose(_ choice: PlayerChoice) {
        guard case .picking(let episode) = stage else { return }
        stage = .playing(episode, choice)
    }

    func cancel() {
        stage = .idle
    }

    /// After the warning: ask unless the user unticked "Спрашивать всегда".
    private func next(after episode: Episode) -> Stage {
        preferences.alwaysAsk ? .picking(episode) : .playing(episode, preferences.choice)
    }
}

extension View {
    /// Attaches the warning dialog, the picker and the full-screen player to a
    /// screen that lists episodes.
    @MainActor
    func episodePlayback(
        _ launcher: EpisodeLauncher,
        releaseTitle: String,
        onProgress: @escaping (Episode, TimeInterval) -> Void,
        onFinished: @escaping (Episode) -> Void
    ) -> some View {
        modifier(EpisodePlaybackModifier(
            launcher: launcher,
            releaseTitle: releaseTitle,
            onProgress: onProgress,
            onFinished: onFinished
        ))
    }
}

@MainActor
struct EpisodePlaybackModifier: ViewModifier {
    let launcher: EpisodeLauncher
    let releaseTitle: String
    let onProgress: (Episode, TimeInterval) -> Void
    let onFinished: (Episode) -> Void

    func body(content: Content) -> some View {
        content
            .alert(
                "Предупреждение",
                isPresented: Binding(
                    get: { if case .warning = launcher.stage { true } else { false } },
                    set: { if !$0 { launcher.cancel() } }
                )
            ) {
                Button("Отмена", role: .cancel) { launcher.cancel() }
                Button("Понятно") { launcher.acceptWarning() }
            } message: {
                Text("Вы открываете видео, которое размещено на стороннем источнике. "
                     + "Администрация приложения не несёт ответственности за его содержимое, "
                     + "а также не гарантирует работоспособность.")
            }
            .sheet(isPresented: Binding(
                get: { if case .picking = launcher.stage { true } else { false } },
                set: { if !$0, case .picking = launcher.stage { launcher.cancel() } }
            )) {
                PlayerPickerSheet(
                    preferences: launcher.preferences,
                    supportsDirectPlayback: !(launcher.pendingEpisode?.isEmbed ?? true),
                    onContinue: { launcher.choose($0) }
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { if case .playing = launcher.stage { true } else { false } },
                set: { if !$0 { launcher.cancel() } }
            )) {
                if case .playing(let episode, let choice) = launcher.stage {
                    PlayerScreen(
                        episode: episode,
                        releaseTitle: releaseTitle,
                        preferences: launcher.preferences,
                        onProgress: { onProgress(episode, $0) },
                        onFinished: { onFinished(episode) },
                        choice: choice
                    )
                }
            }
    }
}
