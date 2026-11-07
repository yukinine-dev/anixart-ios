import SwiftUI
import UIKit
import AnixartKit

/// Release metadata, viewer actions and the Android-compatible detail routes.
@MainActor
struct ReleaseDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.returnToHome) private var returnToHome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false

    let releaseID: Int
    var preloaded: Release?

    @State private var viewer: ProfileViewerKey?
    @State private var model: ReleaseDetailViewModel?
    @State private var isShowingListPicker = false
    @State private var isShowingRating = false
    @State private var isShowingCollectionPicker = false
    @State private var isShowingTitles = false
    @State private var isDescriptionExpanded = false
    @State private var screenshotGallery: ReleaseScreenshotPresentation?
    @State private var report: ProfileReportPresentation?
    @State private var openComment: ReleaseComment?

    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    init(releaseID: Int, preloaded: Release? = nil, viewer: ProfileViewerKey? = nil) {
        self.releaseID = releaseID
        self.preloaded = preloaded
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        ScrollView {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let model {
                if let release = model.release {
                    if let error = model.errorMessage {
                        StatusMessageView(title: "Не удалось обновить данные релиза", message: error,
                                          systemImage: "wifi.exclamationmark", retry: { await model.load() })
                    }
                    content(for: release, model: model)
                        .releaseAccessGate(release: release)
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
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await model?.load() }
        .sheet(isPresented: $isShowingTitles) {
            if let release = model?.release { ReleaseTitlesView(release: release) }
        }
        .navigationDestination(item: $openComment) { comment in
            CommentThreadView(comment: comment, releaseID: releaseID, viewer: viewer)
        }
        .fullScreenCover(item: $screenshotGallery) { presentation in
            ReleaseScreenshotGalleryView(presentation: presentation)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            if model?.release != nil, viewer == env.session.viewerKey {
                Button { isShowingCollectionPicker = true } label: {
                    Label("Выбрать коллекцию", systemImage: "rectangle.stack.badge.plus")
                }
                .accessibilityLabel("Выбрать коллекцию")
            }
        } }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if model == nil {
                model = ReleaseDetailViewModel(
                    releaseID: releaseID,
                    preloaded: preloaded,
                    session: env.session,
                    viewer: viewer
                )
            }
            await model?.load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            model?.invalidate()
            isShowingListPicker = false
            isShowingRating = false
            isShowingCollectionPicker = false
            isShowingTitles = false
            screenshotGallery = nil
            report = nil
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

    // The page is split into small opaque-typed pieces. One huge ViewBuilder
    // produced a type so deeply nested that the Swift runtime overflowed the
    // main-thread stack while demangling it (crash on opening any release).
    @ViewBuilder
    private func content(for release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            topSection(release, model: model)
            mediaSection(release)
            ratingAndListsSection(release, model: model)
            relatedBlock(release)
            bottomSection(release)
        }
        .padding(.bottom, Theme.Spacing.section)
        .sheet(isPresented: $isShowingListPicker) {
            ListPickerSheet(current: release.listStatus) { status in
                Task { await model.setList(status) }
            }
            .disabled(!model.hasCurrentViewer || model.isPerformingAction)
        }
        .sheet(isPresented: $isShowingRating) {
            RatingSheet(
                current: release.validatedYourVote,
                distribution: release,
                onVote: { score in Task { await model.vote(score) } },
                onRemove: { Task { await model.removeVote() } }
            )
            .disabled(!model.hasCurrentViewer || model.isPerformingAction)
        }
        .sheet(isPresented: $isShowingCollectionPicker) {
            AddToCollectionSheet(releaseID: release.id, viewer: viewer)
        }
        .sheet(item: $report) { ProfileReportView(target: $0) }
    }

    private func topSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ReleaseDetailHeader(release: release, onTitles: { isShowingTitles = true })
            statusRow(release, model: model)
            playBlock(release)
            factLines(release)
            genres(release)
            descriptionBlock(release)
        }
    }

    @ViewBuilder
    private func descriptionBlock(_ release: Release) -> some View {
        if let description = release.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            ReleaseExpandableText(text: description, lineLimit: 5, isExpanded: $isDescriptionExpanded,
                                  onExpand: { expandDescription(fromKeyboard: $0) })
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.row)
        }
    }

    @ViewBuilder
    private func mediaSection(_ release: Release) -> some View {
        if let banners = release.videoBanners, !banners.isEmpty {
            sectionRule
            videoSection(release, banners: banners)
        }
    }

    private func ratingAndListsSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule
            ratingSection(release, model: model)
            listsBlock(release)
            screenshotsBlock(release)
        }
    }

    @ViewBuilder
    private func listsBlock(_ release: Release) -> some View {
        if release.listDistribution.contains(where: { $0.count > 0 }) {
            sectionRule
            listsSection(release)
        }
    }

    @ViewBuilder
    private func screenshotsBlock(_ release: Release) -> some View {
        if !release.screenshotURLs.isEmpty {
            sectionRule
            screenshots(release)
        }
    }

    @ViewBuilder
    private func relatedBlock(_ release: Release) -> some View {
        if !release.relatedPreviewReleases.isEmpty || release.hasMoreRelatedReleases {
            sectionRule
            relatedSection(release, releases: release.relatedPreviewReleases)
        }
    }

    private func bottomSection(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule
            collectionLinks(release)
            recommendedBlock(release)
            sectionRule
            commentsSection(release)
        }
    }

    @ViewBuilder
    private func recommendedBlock(_ release: Release) -> some View {
        if let recommended = release.recommendedReleases, !recommended.isEmpty {
            sectionRule
            carousel("Рекомендуем также", releases: recommended)
        }
    }

    private var sectionRule: some View {
        Divider()
            .padding(.horizontal)
            .padding(.vertical, Theme.Spacing.section * 0.75)
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
            .disabled(model.isPerformingAction)

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
            .disabled(model.isPerformingAction)

            NavigationLink {
                CommentsView(releaseID: release.id, releaseTitle: release.displayTitle, viewer: viewer)
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
            HStack(spacing: 12) {
                if release.isDeleted == true {
                    Label("Релиз удалён", systemImage: "exclamationmark.triangle")
                        .font(.ax(.headline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                } else {
                    ReleasePlaybackButton(release: release, viewer: viewer)
                }
                releaseMenu(release)
            }

            if release.isDeleted != true {
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

    private func releaseMenu(_ release: Release) -> some View {
        Menu {
            ShareLink(item: release.shareURL) { Label("Поделиться", systemImage: "square.and.arrow.up") }
            Button { UIPasteboard.general.url = release.shareURL } label: { Label("Скопировать ссылку", systemImage: "link") }
            Button { returnToHome?.callAsFunction() } label: { Label("На главный экран", systemImage: "house") }
                .disabled(returnToHome == nil)
            Button {
                guard viewer == env.session.viewerKey else { return }
                guard let account = viewer?.account else { env.session.isPresentingAuth = true; return }
                report = ProfileReportPresentation(kind: .release, entityID: release.id, title: release.displayTitle, account: account)
            } label: { Label("Пожаловаться", systemImage: "flag") }
        } label: {
            Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                .font(.ax(.title3)).frame(width: 44, height: 48)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Действия с релизом")
        .disabled(viewer != env.session.viewerKey)
    }

    // MARK: - Fact lines

    @ViewBuilder
    private func factLines(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let line = release.countryAndSeasonLine {
                factLine("globe", line, flag: release.countryFlag)
            }
            if let line = release.episodesAndDurationLine {
                factLine("play.rectangle", line)
            }
            if let line = release.broadcastLine {
                factLine("calendar", line)
            }
            if let source = release.sourceMaterialName {
                if let destination = release.sourceMaterialSearch, let viewer {
                    NavigationLink { SourceMaterialSearchView(source: destination, viewer: viewer) } label: {
                        factLine("target", "Первоисточник \(source)", underlined: source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Первоисточник: \(source)")
                } else {
                    factLine("target", "Первоисточник \(source)", underlined: source)
                        .accessibilityHint("Ссылка недоступна")
                }
            }
            ReleaseCreditsLine(release: release, viewer: viewer)
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.section)
    }

    private func factLine(_ systemImage: String, _ text: String, underlined: String? = nil, flag: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let flag { Text(flag).accessibilityHidden(true) }
                else { Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true) }
            }
                .font(.ax(.title3))
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
            FlowRow(spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, genre in
                    NavigationLink {
                        GenreReleasesView(genres: [genre], viewer: viewer)
                    } label: {
                        Text(genre + (index < list.count - 1 ? "," : ""))
                            .underline().font(.ax(.subheadline)).foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.section)
        }
    }

    private func expandDescription(fromKeyboard: Bool = false) {
        guard !isDescriptionExpanded else { return }
        motion.perform(animated: !fromKeyboard, using: .default) { isDescriptionExpanded = true }
    }

    // MARK: - Video

    private func videoSection(_ release: Release, banners: [ReleaseVideoBanner]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Видео") {
                NavigationLink("Показать все") { ReleaseVideosView(release: release, viewer: viewer) }
                    .font(.ax(.subheadline))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.row) {
                    ForEach(Array(banners.enumerated()), id: \.offset) { _, banner in
                        videoBanner(banner, release: release)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func videoBanner(_ banner: ReleaseVideoBanner, release: Release) -> some View {
        switch banner.destination {
        case .category(let id):
            NavigationLink {
                ReleaseVideosView(release: release, categoryID: id, categoryTitle: banner.name, viewer: viewer)
            } label: { videoBannerContent(banner) }
            .buttonStyle(.plain)
        case .web(let url):
            Link(destination: url) { videoBannerContent(banner) }.buttonStyle(.plain)
        case nil:
            videoBannerContent(banner).accessibilityHint("Ссылка недоступна")
        }
    }

    private func videoBannerContent(_ banner: ReleaseVideoBanner) -> some View {
        ZStack {
            CachedAsyncImage(url: AnixartURL.image(banner.image), maxPixelSize: 520) { image in
                image.resizable().scaledToFill()
            } placeholder: { Rectangle().fill(.quaternary) }
            .overlay(.black.opacity(0.35))
            Text(banner.name ?? "Видео").font(.ax(.title2, .medium)).foregroundStyle(.white)
        }
        .frame(width: 260, height: 146)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Rating

    private func ratingSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Рейтинг")

            HStack(alignment: .center, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(release.ratingDetailText ?? "—")
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
                current: release.validatedYourVote ?? 0,
                onVote: { score in
                    guard let vote = ReleaseVote(rawValue: score) else { return }
                    Task { await model.vote(vote) }
                },
                onRemove: { Task { await model.removeVote() } }
            )
            .disabled(model.isPerformingAction)
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
        let urls = release.screenshotURLs
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Кадры")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        Button {
                            guard let viewer, viewer == env.session.viewerKey else { return }
                            screenshotGallery = ReleaseScreenshotPresentation(urls: urls, initialIndex: index, viewer: viewer)
                        } label: {
                            CachedAsyncImage(url: url, maxPixelSize: 520) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть кадр \(index + 1) из \(urls.count)")
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func relatedSection(_ release: Release, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Связанные релизы") {
                if release.hasMoreRelatedReleases, let related = release.related {
                    NavigationLink("Показать все") {
                        RelatedReleasesView(related: related, viewer: viewer, context: .release(release.id))
                    }
                    .font(.ax(.subheadline))
                }
            }
            VStack(spacing: Theme.Spacing.row) {
                ForEach(releases) { item in
                    NavigationLink {
                        ReleaseDetailView(releaseID: item.id, preloaded: item, viewer: viewer)
                    } label: {
                        RelatedReleaseRow(release: item, isCurrent: item.id == release.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.id == release.id)
                }
            }
            .padding(.horizontal)
        }
    }

    private func collectionLinks(_ release: Release) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                ReleaseCollectionsView(releaseID: release.id, title: release.displayTitle, viewer: viewer)
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
        }
    }

    private func carousel(_ title: String, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.Spacing.row) {
                    ForEach(releases) { item in
                        NavigationLink {
                            ReleaseDetailView(releaseID: item.id, preloaded: item, viewer: viewer)
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
                    CommentsView(releaseID: release.id, releaseTitle: release.displayTitle, viewer: viewer)
                }
                .font(.ax(.subheadline, .medium))
                .foregroundStyle(.primary)
            }
            .padding(.horizontal)

            if let comments = release.comments, !comments.isEmpty {
                ForEach(comments.prefix(3)) { comment in
                    CommentRow(
                        comment: comment,
                        onReply: { openComment = comment },
                        onVote: { vote in
                            guard let model else { return }
                            Task { await model.voteComment(comment, vote) }
                        },
                        onOpenReplies: { openComment = comment },
                        isVoting: model?.isPerformingAction ?? false
                    )
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
    var isCurrent = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(release.displayTitle)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if isCurrent {
                    Text("Вы здесь").font(.ax(.caption, .medium)).foregroundStyle(Theme.accent)
                }
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
                }
                ReleaseMetadataBadges(release: release)
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
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .greatestFiniteMagnitude
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
        let fitted = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(0, x - spacing)
        return CGSize(width: fitted, height: y + lineHeight)
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
