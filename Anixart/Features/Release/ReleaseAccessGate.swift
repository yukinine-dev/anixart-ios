import SwiftUI
import AnixartKit
import Lottie

/// Device-local acknowledgement, not a server permission or a way around blocks.
enum ReleaseAccessPolicy {
    static let adultAcknowledgementKey = "release.adultAcknowledged.v1"

    static func requiresAdultConfirmation(_ release: Release, acknowledged: Bool) -> Bool {
        // Release ratings are 1-based; the filter's separate picker is 0-based.
        !acknowledged && release.ageRating == 5
    }

    static func playbackMessage(_ release: Release) -> String? {
        if release.isDeleted == true { return "Релиз удалён" }
        guard release.isRuBlocked == true || release.isViewBlocked == true || release.isPlayDisabled == true else { return nil }
        let reason = release.isRuBlocked == true || release.isViewBlocked == true
            ? "Недоступно в вашей стране. Просмотр данного релиза недоступен."
            : "Просмотр данного релиза недоступен."
        // Licensing wording is supplied by the release, not inferred from flags.
        let note = release.note?.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let note, !note.isEmpty else { return reason }
        return reason + "\n\n" + note
    }
}

@MainActor
private struct ReleaseAccessGate: ViewModifier {
    let release: Release
    @AppStorage(ReleaseAccessPolicy.adultAcknowledgementKey) private var acknowledged = false
    @Environment(\.dismiss) private var dismiss
    @State private var showsConfirmation = false

    private var needsConfirmation: Bool {
        ReleaseAccessPolicy.requiresAdultConfirmation(release, acknowledged: acknowledged)
    }

    func body(content: Content) -> some View {
        Group {
            if needsConfirmation {
                VStack(spacing: 16) {
                    Text("Материалы для взрослых · 18+").font(.ax(.headline))
                    Button("Подтвердить возраст") { showsConfirmation = true }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            } else {
                content
            }
        }
        .task(id: needsConfirmation) { showsConfirmation = needsConfirmation }
        .sheet(isPresented: $showsConfirmation) {
            ScrollView {
                VStack(spacing: 20) {
                    ReleaseAdultWarningArtwork()
                    Text("Возрастное ограничение").font(.ax(.title2, .semibold))
                    Text("Для просмотра подтвердите, что Вам уже исполнилось 18 лет")
                        .font(.ax(.body))
                        .multilineTextAlignment(.center)
                    Button("Да, мне есть 18") {
                        acknowledged = true
                        showsConfirmation = false
                    }
                    .buttonStyle(.borderedProminent)
                    Text("После подтверждения это сообщение больше не будет показываться до выхода из аккаунта.")
                        .font(.ax(.caption)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Назад", role: .cancel) {
                        showsConfirmation = false
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
    }
}

/// Original include_adult_waring artwork: authored three-second Lottie loop,
/// not a replacement GIF. The shared renderer pauses when motion is disallowed.
@MainActor
private struct ReleaseAdultWarningArtwork: View {
    private static let animation = LottieAnimation.named("sticker_4")
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @State private var isVisible = false

    var body: some View {
        Group {
            if let animation = Self.animation {
                ProfileBadgeLottieView(animation: animation, isAnimating: ProfileBadgePlayback.allowsAnimation(
                    isVisible: isVisible, isActive: scenePhase == .active,
                    reduceMotion: reduceMotion, resourceSaving: resourceSaving
                ))
            } else {
                Text("18+").font(.ax(.largeTitle, .bold))
            }
        }
        .frame(height: 180)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

extension View {
    @MainActor
    func releaseAccessGate(release: Release) -> some View {
        modifier(ReleaseAccessGate(release: release))
    }
}

@MainActor
struct ReleasePlaybackButton: View {
    @Environment(AppEnvironment.self) private var env
    let release: Release
    var viewer: ProfileViewerKey?
    @State private var isShowingEpisodes = false
    @State private var isShowingRestriction = false

    var body: some View {
        Button {
            guard viewer == nil || viewer == env.session.viewerKey else { return }
            if ReleaseAccessPolicy.playbackMessage(release) != nil {
                isShowingRestriction = true
            } else {
                isShowingEpisodes = true
            }
        } label: {
            Label(release.continueWatchingText == nil ? "Воспроизвести" : "Продолжить", systemImage: "play.fill")
                .font(.ax(.title3, .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.92), in: Capsule())
                .foregroundStyle(Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .navigationDestination(isPresented: $isShowingEpisodes) {
            EpisodePickerView(release: release, viewer: viewer)
        }
        .alert("Просмотр недоступен", isPresented: $isShowingRestriction) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text(ReleaseAccessPolicy.playbackMessage(release) ?? "Просмотр недоступен")
        }
        .onChange(of: env.session.viewerKey) { _, _ in
            isShowingEpisodes = false
            isShowingRestriction = false
        }
        .onChange(of: release.id) { _, _ in
            isShowingEpisodes = false
            isShowingRestriction = false
        }
    }
}
