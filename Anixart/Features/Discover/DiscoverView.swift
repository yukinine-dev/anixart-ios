import SwiftUI
import AnixartKit

@MainActor
struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: DiscoverViewModel?
    @State private var isShowingSearch = false
    @State private var isShowingSettings = false
    @State private var isShowingFilter = false
    @State private var filter = FilterRequest()
    @State private var appliedFilter: FilterRequest?
    @State private var opened: Release?
    @State private var actionTarget: Release?
    @State private var isShowingRecommendationHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowsingHeader(onSearch: { isShowingSearch = true }, onSettings: { isShowingSettings = true })
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        if let model, model.hasCurrentViewer, !model.banners.isEmpty {
                            BannerCarousel(banners: model.banners, viewer: model.viewer)
                        }
                        shortcuts
                        if let model, model.hasCurrentViewer { content(model) }
                    }
                    .padding(.vertical)
                }
                .refreshable { await model?.load() }
            }
            .navigationTitle("Обзор")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingSearch) { HomeSearchView() }
            .navigationDestination(item: $appliedFilter) { request in
                FilteredReleasesView(filter: request, title: "Результаты фильтра")
            }
            .navigationDestination(item: $opened) { release in
                ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model?.viewer)
            }
            .sheet(item: $actionTarget) { release in
                if let viewer = model?.viewer { ReleaseQuickActionsSheet(release: release, viewer: viewer) }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .alert(RecommendationHelp.title, isPresented: $isShowingRecommendationHelp) {
                Button(RecommendationHelp.dismissTitle, role: .cancel) { }
            } message: { Text(RecommendationHelp.message) }
            .sheet(isPresented: $isShowingFilter) {
                FilterSheet(current: filter, onApply: {
                    filter = $0
                    appliedFilter = $0
                }, onReset: { filter = FilterRequest() })
            }
            .task(id: env.session.viewerKey) {
                if model?.viewer != env.session.viewerKey {
                    model = DiscoverViewModel(session: env.session)
                }
                await model?.loadIfNeeded()
                await env.session.refreshNotificationCount()
            }
            .onChange(of: env.session.viewerKey) { _, _ in
                opened = nil; actionTarget = nil; isShowingRecommendationHelp = false
            }
        }
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink {
                FilteredReleasesView(filter: FilterRequest(sort: .popularDescending), title: "Популярное")
            } label: { shortcutLabel("Популярное", systemImage: "flame") }
            NavigationLink { ScheduleView() } label: { shortcutLabel("Расписание", systemImage: "calendar") }
            NavigationLink { PublicCollectionsView() } label: { shortcutLabel("Коллекции", systemImage: "rectangle.stack") }
            Button { isShowingFilter = true } label: { shortcutLabel("Фильтр", systemImage: "slider.horizontal.3") }
            NavigationLink { RandomReleaseScreen() } label: { shortcutLabel("Рандом", systemImage: "shuffle") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func shortcutLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.ax(.subheadline, .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func content(_ model: DiscoverViewModel) -> some View {
        if model.isLoading && model.isEmpty {
            ProgressView().padding(.vertical, 60)
        } else if let error = model.errorMessage, model.isEmpty {
            StatusMessageView(
                title: "Не удалось загрузить",
                message: error,
                systemImage: "wifi.exclamationmark",
                retry: { await model.load() }
            )
        } else {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if let error = model.partialErrorMessage {
                    StatusMessageView(title: "Некоторые разделы не загрузились", message: error,
                                      systemImage: "wifi.exclamationmark", retry: { await model.load() })
                } else if model.isEmpty, model.viewer.account == nil {
                    StatusMessageView(title: "Пока ничего нет", message: "Обновите обзор позже")
                }
                if !model.continueWatching.isEmpty {
                    carousel("Продолжить просмотр", releases: model.continueWatching, viewer: model.viewer)
                }

                if !model.recommendations.isEmpty {
                    carousel("Рекомендации", subtitle: "На основе ваших оценок", releases: model.recommendations, viewer: model.viewer)
                } else if model.showsRecommendationExplanation {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Рекомендации")
                        Text("На основе ваших оценок").font(.ax(.subheadline)).foregroundStyle(.secondary).padding(.horizontal)
                        Text("Продолжайте смотреть и оценивать аниме. Чем честнее выставлены оценки, тем точнее будут подобраны рекомендации.")
                            .font(.ax(.subheadline)).foregroundStyle(.secondary).padding(.horizontal)
                        Button("Узнать подробнее") { isShowingRecommendationHelp = true }
                            .font(.ax(.subheadline, .medium)).padding(.horizontal)
                    }
                }

                if !model.discussing.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                        SectionHeader(title: "Обсуждаемое сегодня")
                        ForEach(model.discussing) { release in
                            ReleaseListRow(release: release, showsDailyDiscussion: true) { actionTarget = release }
                                .onTapGesture { opened = release }
                                .padding(.horizontal)
                        }
                    }
                }

                if !model.commentsOfTheWeek.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                        SectionHeader(title: "Комментарии недели")
                        ForEach(model.commentsOfTheWeek) { comment in
                            CommentRow(comment: comment, showsRelease: true)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func carousel(_ title: String, subtitle: String? = nil, releases: [Release], viewer: ProfileViewerKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title)
            if let subtitle { Text(subtitle).font(.ax(.subheadline)).foregroundStyle(.secondary).padding(.horizontal) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(releases) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                        } label: {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Editorial banners from `discover/interesting`.
///
/// Paged, endlessly looping carousel. The title and description sit under the
/// picture (as in the Android app) and the page advances every three seconds,
/// but only while the carousel is actually on screen and the app is active.
/// Swiping by hand restarts the three-second timer.
@MainActor
struct BannerCarousel: View {
    let banners: [Interesting]
    let viewer: ProfileViewerKey

    /// How long a banner stays before the next one slides in.
    static let autoAdvanceInterval: Duration = .seconds(3)
    /// The banners are laid out three times so both directions can loop;
    /// the position is silently moved back to the middle copy at the edges.
    private static let copies = 3

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: Int?
    @State private var isOnScreen = false

    private var count: Int { banners.count }

    private struct PlaybackKey: Equatable {
        let isPlaying: Bool
        let position: Int?
    }

    private var isPlaying: Bool { count > 1 && isOnScreen && scenePhase == .active }

    /// Index into `banners` of the page that is currently shown.
    private var currentIndex: Int {
        guard count > 0 else { return 0 }
        return ((position ?? count) % count + count) % count
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(0..<(count * Self.copies), id: \.self) { index in
                        bannerCard(banners[index % count])
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .onChange(of: position) { _, value in recenter(value) }

            if count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { index in
                        Circle()
                            .fill(index == currentIndex ? Color.primary.opacity(0.8) : Color.primary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: BannerFramePreference.self, value: geometry.frame(in: .global))
            }
        )
        .onPreferenceChange(BannerFramePreference.self) { frame in
            // Visible once any part sits below the header and above the screen bottom.
            let visible = frame.maxY > 60 && frame.minY < UIScreen.main.bounds.height
            if visible != isOnScreen { isOnScreen = visible }
        }
        .onAppear {
            if position == nil, count > 0 { position = count }
        }
        .onDisappear { isOnScreen = false }
        .task(id: PlaybackKey(isPlaying: isPlaying, position: position)) {
            guard isPlaying else { return }
            try? await Task.sleep(for: Self.autoAdvanceInterval)
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        let next = (position ?? count) + 1
        if reduceMotion {
            position = next
        } else {
            withAnimation(.easeInOut(duration: 0.45)) { position = next }
        }
    }

    /// Jumps from an outer copy to the identical page in the middle copy, without animation.
    private func recenter(_ value: Int?) {
        guard count > 1, let value, value < count || value >= count * 2 else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position = count + value % count }
    }

    @ViewBuilder
    private func bannerCard(_ banner: Interesting) -> some View {
        switch banner.destination {
        case .release(let id):
            NavigationLink { ReleaseDetailView(releaseID: id, viewer: viewer) } label: { bannerContent(banner) }
                .buttonStyle(.plain)
        case .collection(let id):
            NavigationLink { CollectionByIDView(collectionID: id, viewer: viewer) } label: { bannerContent(banner) }
                .buttonStyle(.plain)
        case .web(let url):
            Link(destination: url) { bannerContent(banner) }.buttonStyle(.plain)
        case nil:
            bannerContent(banner).accessibilityHint("Ссылка недоступна")
        }
    }

    private func bannerContent(_ banner: Interesting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(2, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: AnixartURL.image(banner.image), maxPixelSize: 720) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title ?? "")
                    .font(.ax(.headline))
                    .foregroundStyle(.primary)
                    .lineLimit(2, reservesSpace: true)
                if let description = banner.description, !description.isEmpty {
                    Text(description)
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

private struct BannerFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
