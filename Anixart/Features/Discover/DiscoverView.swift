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
    @State private var isShowingWatchingNow = false
    @State private var isShowingRecommendationHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BrowsingHeader(onSettings: { isShowingSettings = true })
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                        if let model, model.hasCurrentViewer, !model.banners.isEmpty {
                            BannerCarousel(banners: model.banners, viewer: model.viewer)
                        }
                        shortcuts
                        if let model, model.hasCurrentViewer { content(model) }
                    }
                    .padding(.top, 8)
                    // Room for the floating tab bar.
                    .padding(.bottom, 120)
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
            .navigationDestination(item: $commentsTarget) { release in
                CommentsView(releaseID: release.id, releaseTitle: release.displayTitle, viewer: model?.viewer)
            }
            .navigationDestination(isPresented: $isShowingWatchingNow) {
                if let viewer = model?.viewer {
                    DiscoverWatchingView(viewer: viewer)
                }
            }
            .sheet(item: $actionTarget) { release in
                if let viewer = model?.viewer { ReleaseQuickActionsSheet(release: release, viewer: viewer) }
            }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .alert(RecommendationHelp.title, isPresented: $isShowingRecommendationHelp) {
                Button(RecommendationHelp.dismissTitle, role: .cancel) { }
            } message: { Text(RecommendationHelp.message) }
            .sheet(isPresented: $isShowingFilter) {
                DiscoverFilterSheet(current: filter, onApply: {
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
                opened = nil; commentsTarget = nil; actionTarget = nil; isShowingWatchingNow = false; isShowingRecommendationHelp = false
            }
        }
    }

    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            NavigationLink { PopularReleasesView() } label: { OverviewTile(title: "Популярное", systemImage: "flame") }
            NavigationLink { ScheduleView() } label: { OverviewTile(title: "Расписание", systemImage: "calendar") }
            NavigationLink { PublicCollectionsView() } label: { OverviewTile(title: "Коллекции", systemImage: "rectangle.stack") }
            Button { isShowingFilter = true } label: { OverviewTile(title: "Фильтр", systemImage: "slider.horizontal.3") }
            NavigationLink { RandomReleaseScreen() } label: { OverviewTile(title: "Рандом", systemImage: "shuffle") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var socialLinks: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            Link(destination: URL(string: "https://vk.com/anixart_app")!) {
                OverviewTile(title: "Мы ВКонтакте", systemImage: "person.2.fill")
            }
            Link(destination: URL(string: "https://t.me/anixart_app")!) {
                OverviewTile(title: "Мы в Telegram", systemImage: "paperplane.fill")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
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

                if !model.recommendations.isEmpty {
                    OverviewDivider()
                    carousel("Рекомендации", subtitle: "На основе ваших оценок", releases: model.recommendations, viewer: model.viewer)
                } else if model.showsRecommendationExplanation {
                    OverviewDivider()
                    recommendationExplanation
                }

                if !model.discussing.isEmpty {
                    OverviewDivider()
                    VStack(alignment: .leading, spacing: 20) {
                        SectionHeader(title: "Обсуждаемое сегодня")
                        ForEach(model.discussing) { release in
                            OverviewDiscussionRow(release: release) { actionTarget = release }
                                .onTapGesture { opened = release }
                                .padding(.horizontal)
                        }
                    }
                }

                OverviewDivider()
                socialLinks

                if !model.watchingNow.isEmpty {
                    OverviewDivider()
                    VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                        SectionHeader(title: "Смотрят сейчас") {
                            Button("Показать все") { isShowingWatchingNow = true }
                                .font(.ax(.subheadline, .medium))
                                .foregroundStyle(.primary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: Theme.Spacing.row) {
                                ForEach(model.watchingNow) { release in
                                    NavigationLink {
                                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model.viewer)
                                    } label: {
                                        ReleaseCard(release: release, width: 132)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if !model.collectionsOfTheWeek.isEmpty {
                    OverviewDivider()
                    VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                        SectionHeader(title: "Коллекции недели") {
                            NavigationLink { PublicCollectionsView() } label: {
                                Text("Показать все").font(.ax(.subheadline, .medium))
                            }
                            .buttonStyle(.plain)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: Theme.Spacing.row) {
                                ForEach(model.collectionsOfTheWeek) { collection in
                                    NavigationLink {
                                        CollectionByIDView(collectionID: collection.id, viewer: model.viewer)
                                    } label: { OverviewCollectionCard(collection: collection) }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if !model.commentsOfTheWeek.isEmpty {
                    OverviewDivider()
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Комментарии недели")
                        ForEach(model.commentsOfTheWeek) { comment in
                            OverviewCommentCard(comment: comment,
                                                onOpenRelease: { opened = $0 },
                                                onOpenComments: { commentsTarget = $0 })
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }

    private var recommendationExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Рекомендации")
            Text("На основе ваших оценок")
                .font(.ax(.body)).foregroundStyle(.secondary).padding(.horizontal)
            VStack(spacing: 16) {
                Text("Продолжайте смотреть и оценивать аниме. Чем честнее выставлены оценки, тем точнее будут подобраны рекомендации.")
                    .font(.ax(.body)).foregroundStyle(.secondary)
                Button { isShowingRecommendationHelp = true } label: {
                    Text("Узнать подробнее")
                        .font(.ax(.headline, .medium))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.primary.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .padding(.horizontal)
        }
    }

    private func carousel(_ title: String, subtitle: String? = nil, releases: [Release], viewer: ProfileViewerKey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title)
            if let subtitle { Text(subtitle).font(.ax(.body)).foregroundStyle(.secondary).padding(.horizontal) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(releases) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: viewer)
                        } label: {
                            ReleaseCard(release: release, width: 132)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Editorial banners from `discover/interesting`. The new Android beta shows a
/// wide card with its title and text underneath, advances on its own and draws the
/// time to the next banner as a line along the bottom of the card.
@MainActor
struct BannerCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    let banners: [Interesting]
    let viewer: ProfileViewerKey

    @State private var current: Interesting.ID?
    @State private var progress: CGFloat = 0
    @State private var isInteracting = false
    private let interval: Double = 6

    private var currentID: Interesting.ID? { current ?? banners.first?.id }
    private var autoAdvances: Bool { !reduceMotion && !resourceSaving && banners.count > 1 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(banners) { banner in
                    bannerCard(banner)
                        .containerRelativeFrame(.horizontal) { width, _ in width - 56 }
                        .id(banner.id)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in isInteracting = true })
        .task(id: TimerKey(id: currentID.map { "\($0)" } ?? "", interacting: isInteracting)) { await run() }
    }

    private struct TimerKey: Hashable { let id: String; let interacting: Bool }

    private func run() async {
        progress = 0
        guard autoAdvances else { return }
        if isInteracting {
            // Give a manual swipe time to settle before the timer restarts.
            try? await Task.sleep(for: .seconds(1.2))
            isInteracting = false
            return
        }
        withAnimation(.linear(duration: interval)) { progress = 1 }
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled,
              let position = banners.firstIndex(where: { $0.id == currentID }) else { return }
        let next = banners[(position + 1) % banners.count].id
        withAnimation(.easeInOut(duration: 0.45)) { current = next }
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
        let isCurrent = banner.id == currentID
        return VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: AnixartURL.image(banner.image), maxPixelSize: 900) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        Capsule().fill(.white)
                            .frame(width: geometry.size.width * (isCurrent && autoAdvances ? progress : 0), height: 4)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(banner.title ?? "")
                    .font(.ax(.title3, .medium))
                    .lineLimit(2)
                if let description = banner.description, !description.isEmpty {
                    Text(description)
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 6)
        }
    }
}
