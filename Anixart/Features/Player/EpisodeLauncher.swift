import SwiftUI
import AnixartKit

/// The sequence the Android app runs before an episode opens: the warning about
/// third-party sources, then "Выберите плеер" when the user has not told it to
/// stop asking, then the player itself.
///
/// One step more than Android needs. Anixart gives a page rather than a video,
/// so between the warning and the picker the episode's stream has to be found,
/// and that takes a request or two.
@MainActor
@Observable
final class EpisodeLauncher {
    enum Stage: Equatable {
        case idle
        case warning(Episode)
        case resolving(Episode)
        case picking(Episode, PlaybackTarget)
        case playing(Episode, PlayerChoice, PlaybackTarget)
    }

    private(set) var stage: Stage = .idle
    let preferences: PlaybackPreferences

    init(preferences: PlaybackPreferences) {
        self.preferences = preferences
    }

    var pendingEpisode: Episode? {
        switch stage {
        case .warning(let episode), .resolving(let episode): return episode
        case .picking(let episode, _): return episode
        case .playing(let episode, _, _): return episode
        case .idle: return nil
        }
    }

    var isResolving: Bool {
        if case .resolving = stage { return true }
        return false
    }

    func open(_ episode: Episode) {
        if preferences.hasAcceptedDisclaimer {
            resolve(episode)
        } else {
            stage = .warning(episode)
        }
    }

    func acceptWarning() {
        guard case .warning(let episode) = stage else { return }
        preferences.acceptDisclaimer()
        resolve(episode)
    }

    func choose(_ choice: PlayerChoice) {
        guard case .picking(let episode, let target) = stage else { return }
        stage = .playing(episode, choice, target)
    }

    func cancel() {
        stage = .idle
    }

    /// Finds the stream, then asks unless the user unticked "Спрашивать всегда".
    private func resolve(_ episode: Episode) {
        stage = .resolving(episode)
        Task { [weak self] in
            let target = await PlaybackResolver.shared.target(for: episode)
            guard let self, case .resolving(let pending) = self.stage, pending.id == episode.id else { return }
            self.stage = self.preferences.alwaysAsk
                ? .picking(episode, target)
                : .playing(episode, self.preferences.choice, target)
        }
    }
}

extension View {
    /// Attaches the warning dialog, the picker and the full-screen player to a
    /// screen that lists episodes.
    @MainActor
    func episodePlayback(
        _ launcher: EpisodeLauncher,
        releaseTitle: String,
        alternativeSourceName: String? = nil,
        onProgress: @escaping (Episode, TimeInterval) -> Void,
        onFinished: @escaping (Episode) -> Void
    ) -> some View {
        modifier(EpisodePlaybackModifier(
            launcher: launcher,
            releaseTitle: releaseTitle,
            alternativeSourceName: alternativeSourceName,
            onProgress: onProgress,
            onFinished: onFinished
        ))
    }
}

@MainActor
struct EpisodePlaybackModifier: ViewModifier {
    let launcher: EpisodeLauncher
    let releaseTitle: String
    /// A hosting of the same voice-over whose stream can be found, if any.
    let alternativeSourceName: String?
    let onProgress: (Episode, TimeInterval) -> Void
    let onFinished: (Episode) -> Void

    private var target: PlaybackTarget? {
        switch launcher.stage {
        case .picking(_, let target): return target
        case .playing(_, _, let target): return target
        default: return nil
        }
    }

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
            // Finding the stream takes a request or two, and a list that does
            // nothing after a tap looks broken.
            .overlay {
                if launcher.isResolving {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Ищем видео…").font(.ax(.subheadline))
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: Binding(
                get: { if case .picking = launcher.stage { true } else { false } },
                set: { if !$0, case .picking = launcher.stage { launcher.cancel() } }
            )) {
                PlayerPickerSheet(
                    preferences: launcher.preferences,
                    supportsDirectPlayback: target?.supportsDirectPlayback ?? false,
                    streamSourceName: target?.streamSourceName,
                    embeddedNeedsAdvert: KodikWrapper.handles(
                        target?.pageURL ?? URL(string: "about:blank")!
                    ),
                    alternativeSourceName: alternativeSourceName,
                    onContinue: { launcher.choose($0) }
                )
            }
            .fullScreenCover(isPresented: Binding(
                get: { if case .playing = launcher.stage { true } else { false } },
                set: { if !$0 { launcher.cancel() } }
            )) {
                if case .playing(let episode, let choice, let target) = launcher.stage {
                    PlayerScreen(
                        episode: episode,
                        releaseTitle: releaseTitle,
                        preferences: launcher.preferences,
                        onProgress: { onProgress(episode, $0) },
                        onFinished: { onFinished(episode) },
                        choice: choice,
                        target: target
                    )
                }
            }
    }
}
