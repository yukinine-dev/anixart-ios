import SwiftUI
import AnixartKit

/// The release page, laid out as the Android `ReleaseFragment` lays it out: a poster
/// over its own blurred backdrop, the list/bookmark/comment row, the play button with
/// the last added episode under it, the icon fact lines, then the sections.
@MainActor
struct ReleaseDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    var preloaded: Release?

    @State private var model: ReleaseDetailViewModel?
    @State private var isShowingListPicker = false
    @State private var isShowingRating = false
    @State private var isShowingCollectionPicker = false
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
        .navigationTitle("")
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
        VStack(alignment: .leading, spacing: 0) {
            poster(release)
            titleBlock(release)
            statusRow(release, model: model)
            playBlock(release)
            factLines(release)
            genres(release)

            if let description = release.description, !description.isEmpty {
                descriptionBlock(description)
            }

            if let banners = release.videoBanners, !banners.isEmpty {
                sectionRule
                videoSection(release, banners: banners)
            }

            sectionRule
            ratingSection(release, model: model)

            if release.listDistribution.contains(where: { $0.count > 0 }) {
                sectionRule
                listsSection(release)
            }

            if !release.screenshotURLs.isEmpty {
                sectionRule
                screenshots(release)
            }

            if let related = release.relatedReleases, !related.isEmpty {
                sectionRule
                relatedSection(release, releases: related)
            }

            sectionRule
            collectionLinks(release)

            if let recommended = release.recommendedReleases, !recommended.isEmpty {
                sectionRule
                carousel("Рекомендуем также", releases: recommended)
            }

            sectionRule
            commentsSection(release)
        }
        .padding(.bottom, Theme.Spacing.section)
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

    private var sectionRule: some View {
        Divider()
            .padding(.horizontal)
            .padding(.vertical, Theme.Spacing.section * 0.75)
    }

    // MARK: - Poster

    private func poster(_ release: Release) -> some View {
        ZStack {
            // The Android page fills the area behind the poster with the poster
            // itself, blurred and dimmed.
            AsyncImage(url: release.posterURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.clear
            }
            .frame(height: 380)
            .clipped()
            .blur(radius: 28)
            .overlay(.black.opacity(0.45))
            .allowsHitTesting(false)

            AsyncImage(url: release.posterURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary)
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipped()
    }

    // MARK: - Title

    private func titleBlock(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                NavigationLink {
                    ReleaseTitlesView(release: release)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.ax(.title3))
                        .foregroundStyle(.secondary)
                }
                Text(release.displayTitle)
                    .font(.ax(.title2, .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let subtitle = release.displaySubtitle {
                    Text(subtitle)
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let age = release.ageRatingText {
                    Text(age)
                        .font(.ax(.caption2, .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.leading, 32)
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row)
    }

    // MARK: - Status / bookmark / comments

    private func statusRow(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        HStack(spacing: 10) {
            Button {
                isShowingListPicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down").font(.ax(.caption))
                    Text(release.listStatus?.title ?? "Не смотрю")
                        .font(.ax(.subheadline))
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                .foregroundStyle(release.listStatus.map { Theme.listColor($0) } ?? .primary)
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.toggleFavorite() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: (release.isFavorite ?? false) ? "bookmark.fill" : "bookmark")
                        .font(.ax(.subheadline))
                    Text(Format.count(release.favoriteCount))
                        .font(.ax(.subheadline))
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                .foregroundStyle((release.isFavorite ?? false) ? Theme.accent : .primary)
            }
            .buttonStyle(.plain)

            NavigationLink {
                CommentsView(releaseID: release.id, releaseTitle: release.displayTitle)
            } label: {
                Image(systemName: "text.bubble")
                    .font(.ax(.subheadline))
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row)
    }

    // MARK: - Play

    @ViewBuilder
    private func playBlock(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reason = release.playbackBlockedReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.ax(.headline))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            } else {
                HStack(spacing: 12) {
                    NavigationLink {
                        EpisodePickerView(release: release)
                    } label: {
                        Label(
                            release.continueWatchingText == nil ? "Воспроизвести" : "Продолжить",
                            systemImage: "play.fill"
                        )
                        .font(.ax(.title3, .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.92), in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                    }
                    .buttonStyle(.plain)

                    Menu {
                        NavigationLink("Выбрать озвучку", systemImage: "waveform") {
                            EpisodePickerView(release: release)
                        }
                        NavigationLink("Онлайн просмотр", systemImage: "play.rectangle.on.rectangle") {
                            StreamingPlatformsView(release: release)
                        }
                        Button("Оценить", systemImage: "star") { isShowingRating = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.ax(.title3))
                            .frame(width: 24, height: 48)
                    }
                    .foregroundStyle(.primary)
                }

                if let added = release.lastEpisodeAddedLine {
                    Text(added)
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                } else if let continueText = release.continueWatchingText {
                    Text(continueText)
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row + 4)
    }

    // MARK: - Fact lines

    @ViewBuilder
    private func factLines(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = release.countryAndSeasonLine {
                factLine("globe", line)
            }
            if let line = release.episodesAndDurationLine {
                factLine("play.rectangle", line)
            }
            if let line = release.broadcastLine {
                factLine("calendar", line)
            }
            if let source = release.sourceMaterialName {
                factLine("target", "Первоисточник \(source)", underlined: source)
            }
            if let line = release.studioAndDirectorLine {
                factLine("person.3", line)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.section)
    }

    private func factLine(_ systemImage: String, _ text: String, underlined: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.ax(.title3))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Text(attributed(text, underlining: underlined))
                .font(.ax(.subheadline))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Underlines one run inside a line, the way the Android page marks a link.
    private func attributed(_ text: String, underlining: String?) -> AttributedString {
        var string = AttributedString(text)
        if let underlining, let range = string.range(of: underlining) {
            string[range].underlineStyle = .single
        }
        return string
    }

    // MARK: - Genres and description

    @ViewBuilder
    private func genres(_ release: Release) -> some View {
        let list = release.genreList
        if !list.isEmpty {
            NavigationLink {
                CatalogView(initialGenres: list)
            } label: {
                Text(underlinedJoin(list))
                    .font(.ax(.subheadline))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.section)
            }
            .buttonStyle(.plain)
        }
    }

    private func underlinedJoin(_ items: [String]) -> AttributedString {
        var result = AttributedString()
        for (index, item) in items.enumerated() {
            var piece = AttributedString(item)
            piece.underlineStyle = .single
            result.append(piece)
            if index < items.count - 1 { result.append(AttributedString(", ")) }
        }
        return result
    }

    private func descriptionBlock(_ description: String) -> some View {
        VStack(spacing: Theme.Spacing.row) {
            Text(description)
                .font(.ax(.subheadline))
                .lineSpacing(3)
                .lineLimit(isDescriptionExpanded ? nil : 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !isDescriptionExpanded {
                Button("Подробнее...") {
                    withAnimation { isDescriptionExpanded = true }
                }
                .font(.ax(.subheadline, .medium))
                .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row)
    }

    // MARK: - Video

    private func videoSection(_ release: Release, banners: [ReleaseVideoBanner]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Видео") {
                NavigationLink("Показать все") { ReleaseVideosView(release: release) }
                    .font(.ax(.subheadline))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.row) {
                    ForEach(Array(banners.enumerated()), id: \.offset) { _, banner in
                        NavigationLink {
                            ReleaseVideosView(release: release, category: banner.name)
                        } label: {
                            ZStack {
                                AsyncImage(url: AnixartURL.image(banner.image)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                }
                                .overlay(.black.opacity(0.35))
                                Text(banner.name ?? "Видео")
                                    .font(.ax(.title2, .medium))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 260, height: 146)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Rating

    private func ratingSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Рейтинг")

            HStack(alignment: .center, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(release.ratingText ?? "—")
                        .font(.ax(fixed: 54, .bold))
                        .monospacedDigit()
                    Text(Plural.votes(release.voteCount ?? 0))
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                }

                VoteHistogram(distribution: release.voteDistribution)
            }
            .padding(.horizontal)

            StarRatingRow(
                avatarURL: env.session.profile?.avatarURL,
                current: release.yourVote ?? 0,
                onVote: { score in
                    guard let vote = ReleaseVote(rawValue: score) else { return }
                    Task { await model.vote(vote) }
                },
                onRemove: { Task { await model.removeVote() } }
            )
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    // MARK: - Lists

    private func listsSection(_ release: Release) -> some View {
        let distribution = release.listDistribution
        let total = max(1, distribution.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "В списках у людей")

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(distribution, id: \.status) { slice in
                        Theme.listColor(slice.status)
                            .frame(width: max(0, geometry.size.width * CGFloat(slice.count) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            .padding(.horizontal)

            FlowRow(spacing: 14) {
                ForEach(distribution, id: \.status) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.listColor(slice.status)).frame(width: 9, height: 9)
                        Text(slice.status.title).font(.ax(.caption))
                        Text(Format.count(slice.count))
                            .font(.ax(.caption, .medium))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Screenshots, related, collections, recommendations

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
                        .frame(width: 240, height: 135)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func relatedSection(_ release: Release, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Связанные релизы") {
                if let related = release.related {
                    NavigationLink("Показать все") {
                        RelatedReleasesView(relatedID: related.id, title: release.displayTitle)
                    }
                    .font(.ax(.subheadline))
                }
            }
            VStack(spacing: Theme.Spacing.row) {
                ForEach(releases.prefix(3)) { item in
                    NavigationLink {
                        ReleaseDetailView(releaseID: item.id, preloaded: item)
                    } label: {
                        RelatedReleaseRow(release: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func collectionLinks(_ release: Release) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ReleaseCollectionsView(releaseID: release.id, title: release.displayTitle)
            } label: {
                HStack {
                    Text("Показать в коллекциях").font(.ax(.title3, .medium))
                    if let count = release.collectionCount, count > 0 {
                        Text("\(count)")
                            .font(.ax(.caption, .medium))
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal)

            Button {
                isShowingCollectionPicker = true
            } label: {
                HStack {
                    Text("Добавить к себе в коллекцию").font(.ax(.title3, .medium))
                    Spacer()
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .sheet(isPresented: $isShowingCollectionPicker) {
                AddToCollectionSheet(releaseID: release.id)
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

    // MARK: - Comments

    private func commentsSection(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Комментарии").font(.ax(.title3, .semibold))
                    Text("Популярные и актуальные")
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink("Показать все") {
                    CommentsView(releaseID: release.id, releaseTitle: release.displayTitle)
                }
                .font(.ax(.subheadline, .medium))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal)

            if let comments = release.comments, !comments.isEmpty {
                ForEach(comments.prefix(3)) { comment in
                    CommentRow(comment: comment)
                        .padding(.horizontal)
                }
            } else {
                Text("Пока нет комментариев")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}

// MARK: - Rating pieces

/// The 5..1 bars next to the average score.
struct VoteHistogram: View {
    let distribution: [(score: Int, count: Int)]

    private var maximum: Int { max(1, distribution.map(\.count).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(distribution, id: \.score) { row in
                HStack(spacing: 8) {
                    Text("\(row.score)")
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule()
                                .fill(Color.primary.opacity(0.85))
                                .frame(width: max(8, geometry.size.width * CGFloat(row.count) / CGFloat(maximum)))
                        }
                    }
                    .frame(height: 9)
                }
            }
        }
    }
}

/// The viewer's avatar next to five tappable stars.
@MainActor
struct StarRatingRow: View {
    let avatarURL: URL?
    let current: Int
    let onVote: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Avatar(url: avatarURL, size: 42)
            Spacer(minLength: 12)
            ForEach(1...5, id: \.self) { score in
                Button {
                    if score == current { onRemove() } else { onVote(score) }
                } label: {
                    Image(systemName: score <= current ? "star.fill" : "star")
                        .font(.ax(fixed: 26))
                        .foregroundStyle(score <= current ? Theme.accent : .secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A related release, as the Android list draws it: poster, title, year, score, category.
@MainActor
struct RelatedReleaseRow: View {
    let release: Release

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(release.displayTitle)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    if let year = release.year, !year.isEmpty {
                        Text("\(year) год")
                            .font(.ax(.subheadline))
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
                    }
                    if let rating = release.ratingText {
                        HStack(spacing: 3) {
                            Text(rating).font(.ax(.subheadline)).foregroundStyle(.secondary)
                            Image(systemName: "star.fill").font(.ax(.caption2)).foregroundStyle(.secondary)
                        }
                    }
                    if let category = release.category?.name {
                        Text(category)
                            .font(.ax(.caption))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Wraps its children onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
