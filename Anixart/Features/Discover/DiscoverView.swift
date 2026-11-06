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
                opened = nil; actionTarget = nil; isShowingWatchingNow = false; isShowingRecommendationHelp = false
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
                if !model.watchingNow.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.row) {
                        SectionHeader(title: "Смотрят сейчас") {
                            Button("Показать все") { isShowingWatchingNow = true }
                                .font(.ax(.subheadline, .medium))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: Theme.Spacing.row) {
                                ForEach(model.watchingNow) { release in
                                    NavigationLink {
                                        ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model.viewer)
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
@MainActor
struct BannerCarousel: View {
    let banners: [Interesting]
    let viewer: ProfileViewerKey

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.row) {
                ForEach(banners) { banner in
                    bannerCard(banner)
                }
            }
            .padding(.horizontal)
        }
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
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: AnixartURL.image(banner.image), maxPixelSize: 520) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 300, height: 150)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.75), .clear],
                startPoint: .bottom,
                endPoint: .top
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title ?? "")
                    .font(.ax(.headline))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let description = banner.description, !description.isEmpty {
                    Text(description)
                        .font(.ax(.caption))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(width: 300, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
