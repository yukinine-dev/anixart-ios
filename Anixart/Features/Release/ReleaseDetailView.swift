import SwiftUI
import AnixartKit

@MainActor
struct ReleaseDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    var preloaded: Release?

    @State private var model: ReleaseDetailViewModel?
    @State private var isShowingListPicker = false
    @State private var isShowingRating = false
    @State private var isDescriptionExpanded = false

    var body: some View {
        ScrollView {
            if let model {
                if let release = model.release {
                    content(for: release, model: model)
                } else if let error = model.errorMessage {
                    StatusMessageView(
                        title: "Не удалось загрузить релиз",
                        message: error,
                        systemImage: "wifi.exclamationmark",
                        retry: { await model.load() }
                    )
                } else {
                    ProgressView().padding(.vertical, 60)
                }
            }
        }
        .navigationTitle(model?.release?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = ReleaseDetailViewModel(
                    releaseID: releaseID,
                    preloaded: preloaded,
                    client: env.client,
                    session: env.session
                )
            }
            await model?.load()
        }
        .alert(
            "Не получилось",
            isPresented: Binding(
                get: { model?.actionError != nil },
                set: { if !$0 { model?.dismissActionError() } }
            )
        ) {
            Button("Понятно", role: .cancel) { model?.dismissActionError() }
        } message: {
            Text(model?.actionError ?? "")
        }
    }

    @ViewBuilder
    private func content(for release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.section) {
            header(release)
            actions(release, model: model)

            if let description = release.description, !description.isEmpty {
                descriptionSection(description)
            }

            metadata(release)

            if !release.screenshotURLs.isEmpty {
                screenshots(release)
            }

            if let related = release.relatedReleases, !related.isEmpty {
                carousel("Связанное", releases: related)
            }

            if let recommended = release.recommendedReleases, !recommended.isEmpty {
                carousel("Похожее", releases: recommended)
            }

            commentsSection(release)
        }
        .padding(.vertical)
    }

    // MARK: - Header

    private func header(_ release: Release) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: 120)

            VStack(alignment: .leading, spacing: 6) {
                Text(release.displayTitle).font(.headline)
                if let subtitle = release.displaySubtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    RatingBadge(grade: release.ratingValue)
                    if let votes = release.voteCount, votes > 0 {
                        Text("\(Format.count(votes)) оценок")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let category = release.category?.name {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
                if let status = release.status?.name {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if let seasonYear = release.seasonAndYear {
                    Text(seasonYear).font(.caption).foregroundStyle(.secondary)
                }
                if let age = release.ageRatingText {
                    Text(age)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(spacing: Theme.Spacing.row) {
            if let reason = release.playbackBlockedReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            } else {
                NavigationLink {
                    EpisodePickerView(release: release)
                } label: {
                    Label(
                        release.continueWatchingText.map { "Продолжить · \($0)" } ?? "Смотреть",
                        systemImage: "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
            }

            HStack(spacing: Theme.Spacing.row) {
                Button {
                    isShowingListPicker = true
                } label: {
                    actionTile(
                        title: release.listStatus?.title ?? "В список",
                        systemImage: release.listStatus?.systemImage ?? "plus.circle",
                        isActive: release.listStatus != nil
                    )
                }

                Button {
                    Task { await model.toggleFavorite() }
                } label: {
                    actionTile(
                        title: "Избранное",
                        systemImage: (release.isFavorite ?? false) ? "heart.fill" : "heart",
                        isActive: release.isFavorite ?? false
                    )
                }

                Button {
                    isShowingRating = true
                } label: {
                    actionTile(
                        title: release.yourVote.map { "Ваша: \($0)" } ?? "Оценить",
                        systemImage: (release.yourVote ?? 0) > 0 ? "star.fill" : "star",
                        isActive: (release.yourVote ?? 0) > 0
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .sheet(isPresented: $isShowingListPicker) {
            ListPickerSheet(current: release.listStatus) { status in
                Task { await model.setList(status) }
            }
        }
        .sheet(isPresented: $isShowingRating) {
            RatingSheet(
                current: release.yourVote,
                distribution: release,
                onVote: { score in Task { await model.vote(score) } },
                onRemove: { Task { await model.removeVote() } }
            )
        }
    }

    private func actionTile(title: String, systemImage: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3)
            Text(title).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            isActive ? Theme.accent.opacity(0.15) : Color.primary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .foregroundStyle(isActive ? Theme.accent : .primary)
    }

    // MARK: - Sections

    private func descriptionSection(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            SectionHeader(title: "Описание")
            Text(description)
                .font(.subheadline)
                .lineLimit(isDescriptionExpanded ? nil : 5)
                .padding(.horizontal)
            Button(isDescriptionExpanded ? "Свернуть" : "Читать далее") {
                withAnimation { isDescriptionExpanded.toggle() }
            }
            .font(.subheadline)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func metadata(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.inline) {
            SectionHeader(title: "О релизе")
            VStack(alignment: .leading, spacing: 6) {
                if !release.genreList.isEmpty {
                    metadataRow("Жанры", release.genreList.joined(separator: ", "))
                }
                if let episodes = release.episodeProgressText {
                    metadataRow("Эпизоды", episodes)
                }
                if let duration = Format.episodeDuration(release.duration) {
                    metadataRow("Длительность", duration)
                }
                if let studio = release.studio, !studio.isEmpty {
                    metadataRow("Студия", studio)
                }
                if let director = release.director, !director.isEmpty {
                    metadataRow("Режиссёр", director)
                }
                if let author = release.author, !author.isEmpty {
                    metadataRow("Автор", author)
                }
                if let country = release.country, !country.isEmpty {
                    metadataRow("Страна", country)
                }
                if let date = release.releaseDate, !date.isEmpty {
                    metadataRow("Выход", date)
                }
            }
            .padding(.horizontal)
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value).font(.caption)
            Spacer(minLength: 0)
        }
    }

    private func screenshots(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Кадры")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(release.screenshotURLs, id: \.self) { url in
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 220, height: 124)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func carousel(_ title: String, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(releases) { item in
                        NavigationLink {
                            ReleaseDetailView(releaseID: item.id, preloaded: item)
                        } label: {
                            ReleaseCard(release: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func commentsSection(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Комментарии") {
                NavigationLink("Все \(Format.count(release.commentCount))") {
                    CommentsView(releaseID: release.id, releaseTitle: release.displayTitle)
                }
                .font(.subheadline)
            }

            if let comments = release.comments, !comments.isEmpty {
                ForEach(comments.prefix(3)) { comment in
                    CommentRow(comment: comment)
                        .padding(.horizontal)
                }
            } else {
                Text("Пока нет комментариев")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}
