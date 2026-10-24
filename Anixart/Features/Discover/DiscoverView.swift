import SwiftUI
import AnixartKit

@MainActor
struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: DiscoverViewModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model {
                    content(model)
                }
            }
            .navigationTitle("Обзор")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ScheduleView()
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .refreshable { await model?.load() }
            .task {
                if model == nil {
                    model = DiscoverViewModel(client: env.client, session: env.session)
                }
                await model?.loadIfNeeded()
            }
        }
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
                if !model.banners.isEmpty {
                    BannerCarousel(banners: model.banners)
                }

                if !model.continueWatching.isEmpty {
                    carousel("Продолжить просмотр", releases: model.continueWatching)
                }

                if !model.recommendations.isEmpty {
                    carousel("Рекомендации", releases: model.recommendations)
                }

                if !model.discussing.isEmpty {
                    carousel("Сейчас обсуждают", releases: model.discussing)
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

    private func carousel(_ title: String, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(releases) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release)
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

    private func bannerCard(_ banner: Interesting) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: AnixartURL.image(banner.image)) { image in
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
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let description = banner.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
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
