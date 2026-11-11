import SwiftUI
import AnixartKit

/// «Продолжить просмотр»: the last watched episode from the history, shown on
/// Главная and Закладки. It can be closed with the cross or swiped away, and is
/// switched off in Настройки → Внешний вид → Продолжить просмотр.
@MainActor
struct ContinueWatchingCard: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(DeviceAppearancePreferenceKey.continueWatching) private var isEnabled = true
    @AppStorage(DeviceAppearancePreferenceKey.continueWatchingDismissed) private var dismissedKey = ""
    @State private var release: Release?
    @State private var viewer: ProfileViewerKey?
    @State private var dragOffset: CGFloat = 0
    @State private var isOpen = false

    private var key: String? {
        release.map { "\($0.id)|\($0.continueWatchingText ?? "")" }
    }

    private var fadeAmount: Double {
        let progress: Double = min(Double(abs(dragOffset)) / 240.0, 0.8)
        return 1.0 - progress
    }

    var body: some View {
        Group {
            if isEnabled, let release, let key, key != dismissedKey, let viewer, viewer == env.session.viewerKey {
                card(release)
                    .offset(x: dragOffset)
                    .opacity(fadeAmount)
                    .gesture(
                        DragGesture(minimumDistance: 16)
                            .onChanged { dragOffset = $0.translation.width }
                            .onEnded { value in
                                if abs(value.translation.width) > 100 {
                                    withAnimation(.easeOut(duration: 0.2)) { dismissedKey = key }
                                }
                                withAnimation(.spring) { dragOffset = 0 }
                            }
                    )
                    .navigationDestination(isPresented: $isOpen) {
                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                    }
                    .transition(.opacity)
            }
        }
        .task(id: env.session.viewerKey) { await load() }
    }

    private func card(_ release: Release) -> some View {
        Button { isOpen = true } label: {
            HStack(spacing: 14) {
                ReleasePoster(url: release.posterURL, width: 44, cornerRadius: 10, aspectRatio: 2.0 / 3.0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Продолжить просмотр").font(.ax(.caption)).foregroundStyle(.secondary)
                    Text(release.displayTitle).font(.ax(.subheadline, .medium)).lineLimit(1)
                    if let episode = release.continueWatchingText {
                        Text(episode).font(.ax(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.18), in: Circle())
                Button {
                    if let key { withAnimation { dismissedKey = key } }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func load() async {
        let current = env.session.viewerKey
        release = nil
        guard current.account != nil else { return }
        let page = try? await env.session.sendViewerRequest(BookmarkEndpoints.history(page: 0), for: current)
        guard current == env.session.viewerKey else { return }
        release = page?.items.first(where: { $0.continueWatchingText != nil })
        viewer = current
    }
}
