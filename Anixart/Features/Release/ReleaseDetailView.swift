import SwiftUI
import UIKit
import AnixartKit

/// Release metadata, viewer actions and the Android-compatible detail routes.
@MainActor
struct ReleaseDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.returnToHome) private var returnToHome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appThemePalette) private var palette
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
    @State private var inlineReply: ReleaseComment?
    @State private var inlineComposer = ProfileCommentDraft()
    @State private var inlineThread: ReleaseComment?
    @State private var inlineVotingIDs = Set<Int>()
    @State private var inlineCommentError: String?

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
        // The blurred poster runs under the bar, as on Android.
        .toolbarBackground(.hidden, for: .navigationBar)
        .refreshable { await model?.load() }
        .sheet(isPresented: $isShowingTitles) {
            if let release = model?.release { ReleaseTitlesView(release: release) }
        }
        .fullScreenCover(item: $screenshotGallery) { presentation in
            ReleaseScreenshotGalleryView(presentation: presentation)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarLeading) { backButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { backButton }
            }
            if #available(iOS 26, *) {
                ToolbarItem(placement: .topBarTrailing) { collectionButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { collectionButton }
            }
        }
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
        .alert("Комментарии", isPresented: Binding(
            get: { inlineCommentError != nil },
            set: { if !$0 { inlineCommentError = nil } }
        )) {
            Button("Понятно", role: .cancel) { inlineCommentError = nil }
        } message: {
            Text(inlineCommentError ?? "")
        }
    }

    @ViewBuilder
    private func content(for release: Release, model: ReleaseDetailViewModel) -> some View {
        // Three erased groups: one 17-child VStack made a generic type deep enough to
        // overflow the main-thread stack while the Swift runtime demangled it.
        VStack(alignment: .leading, spacing: 0) {
            AnyView(detailTop(release, model: model))
            AnyView(detailMiddle(release, model: model))
            AnyView(detailBottom(release, model: model))
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
        .sheet(item: $inlineReply) { comment in
            CommentsView(
                releaseID: release.id,
                releaseTitle: release.displayTitle,
                viewer: viewer,
                initialReplyTo: comment
            )
        }
    }

    @ViewBuilder
    private func detailTop(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            ReleaseDetailHeader(release: release, onTitles: { isShowingTitles = true }, onPoster: {
                guard let viewer, viewer == env.session.viewerKey, let url = release.posterURL else { return }
                screenshotGallery = ReleaseScreenshotPresentation(urls: [url], initialIndex: 0, viewer: viewer, title: "Постер")
            })
            statusRow(release, model: model)
            playBlock(release)
            factLines(release)
            genres(release)

            if let description = release.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                ReleaseExpandableText(text: description, lineLimit: 5, isExpanded: $isDescriptionExpanded,
                                      onExpand: { expandDescription(fromKeyboard: $0) })
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.row)
            }
    }

    @ViewBuilder
    private func detailMiddle(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            if let banners = release.videoBanners, !banners.isEmpty {
                sectionRule
                videoSection(release, banners: banners)
            }

            // Android hides the whole rating block for an announced (unreleased) title.
            if release.status?.id != AiringStatus.announced.rawValue {
                sectionRule
                ratingSection(release, model: model)
            }

            if release.listDistribution.contains(where: { $0.count > 0 }) {
                sectionRule
                listsSection(release)
            }

            if !release.screenshotURLs.isEmpty {
                sectionRule
                screenshots(release)
            }
    }

    @ViewBuilder
    private func detailBottom(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            if !release.relatedPreviewReleases.isEmpty || release.hasMoreRelatedReleases {
                sectionRule
                relatedSection(release, releases: release.relatedPreviewReleases)
            }

            sectionRule
            collectionLinks(release)

            if let recommended = release.recommendedReleases, !recommended.isEmpty {
                sectionRule
                recommendedCarousel(releases: recommended)
                    .padding(.vertical, 16)
                    .background(palette.surface.color)
            }

            sectionRule
            commentsSection(release, model: model)
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
                .overlay(Capsule().stroke(release.listStatus.map { Theme.listColor($0) } ?? Color.primary.opacity(0.25), lineWidth: 1.5))
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
                    Text(Format.exact(release.favoriteCount))
                        .font(.ax(.subheadline))
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .overlay(Capsule().stroke((release.isFavorite ?? false) ? Theme.favoriteYellow : Color.primary.opacity(0.25), lineWidth: 1.5))
                .foregroundStyle((release.isFavorite ?? false) ? Theme.favoriteYellow : .primary)
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
                    .overlay(Capsule().stroke(Color.primary.opacity(0.25), lineWidth: 1.5))
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
        let caption: String? = release.isDeleted == true ? nil : (release.lastEpisodeAddedLine ?? release.continueWatchingText)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                if release.isDeleted == true {
                    Label("Релиз удалён", systemImage: "exclamationmark.triangle")
                        .font(.ax(.headline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                } else {
                    ReleasePlaybackButton(release: release, viewer: viewer)
                        .zIndex(1)
                }
                // Android tucks the caption into a dark panel under the button.
                if let caption {
                    Text(caption)
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                        .padding(.bottom, 10)
                        .background(Color.primary.opacity(0.08),
                                    in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous))
                        .padding(.top, -24)
                }
            }
            releaseMenu(release)
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
        VStack(alignment: .leading, spacing: 7) {
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
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let flag { Text(flag).accessibilityHidden(true) }
                else {
                    Image(systemName: systemImage).resizable().scaledToFit()
                        .frame(width: 18, height: 16).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
                .font(.ax(.body))
                .frame(width: 22, alignment: .center)
            Text(attributed(text, underlining: underlined))
                .font(.ax(.footnote))
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
                        HStack(spacing: 0) {
                            Text(genre).underline()
                            if index < list.count - 1 { Text(",") }
                        }
                        .font(.ax(.subheadline)).foregroundStyle(.primary)
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
                    ratingNumber(release)
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

    /// «4.56»: the last digit is drawn smaller, as the Android page does.
    @ViewBuilder
    private func ratingNumber(_ release: Release) -> some View {
        if let text = release.ratingDetailText, text.count >= 3 {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: String(text.dropLast())).font(.ax(fixed: 56, .bold))
                Text(verbatim: String(text.suffix(1))).font(.ax(fixed: 42, .bold))
            }
            .monospacedDigit()
        } else {
            Text(release.ratingDetailText ?? "—").font(.ax(fixed: 54, .bold)).monospacedDigit()
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
            .frame(height: 26)
            .padding(.horizontal)

            // Android lays the legend out in two columns: watching, planned and
            // completed on the left; on hold and dropped on the right.
            let counts = distribution.reduce(into: [ProfileListStatus: Int]()) { $0[$1.status] = $1.count }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 9) {
                GridRow { legendItem(.watching, counts); legendItem(.holdOn, counts) }
                GridRow { legendItem(.plan, counts); legendItem(.dropped, counts) }
                GridRow { legendItem(.completed, counts); Color.clear.frame(width: 1, height: 1) }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func legendItem(_ status: ProfileListStatus, _ counts: [ProfileListStatus: Int]) -> some View {
        if let count = counts[status] {
            HStack(spacing: 8) {
                Circle().fill(Theme.listColor(status)).frame(width: 13, height: 13)
                Text(status.title).font(.ax(fixed: 14.5)).foregroundStyle(.secondary).lineLimit(1)
                Text(Format.exact(count)).font(.ax(fixed: 14.5, .semibold)).monospacedDigit().lineLimit(1)
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    // MARK: - Screenshots, related, collections, recommendations

    private func screenshots(_ release: Release) -> some View {
        let urls = release.screenshotURLs
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
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
                    if item.id == release.id {
                        // Not a disabled link: that would dim the open release to grey.
                        RelatedReleaseRow(release: item, isCurrent: true)
                    } else {
                        NavigationLink {
                            ReleaseDetailView(releaseID: item.id, preloaded: item, viewer: viewer)
                        } label: {
                            RelatedReleaseRow(release: item, isCurrent: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func collectionLinks(_ release: Release) -> some View {
        // The outer section rules already draw the top and bottom lines, so only
        // the one between the two rows lives here (no doubled strokes).
        VStack(spacing: 0) {
            NavigationLink {
                ReleaseCollectionsView(releaseID: release.id, title: release.displayTitle, viewer: viewer)
            } label: {
                HStack {
                    Text("Показать в коллекциях").font(.ax(.title3, .medium))
                    if let count = release.collectionCount, count > 0 {
                        Text(verbatim: String(count))
                            .font(.ax(.subheadline))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    Image(systemName: "plus").font(.system(size: 22, weight: .light)).foregroundStyle(.secondary)
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

    /// «Рекомендуем также» as Android draws it: tall posters, no score badge, the
    /// title in bold on two lines and nothing under it.
    private func recommendedCarousel(releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Рекомендуем также")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(releases) { item in
                        NavigationLink {
                            ReleaseDetailView(releaseID: item.id, preloaded: item, viewer: viewer)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                ReleasePoster(url: item.posterURL, width: 118, cornerRadius: 22, aspectRatio: 2.0 / 3.0)
                                Text(item.displayTitle)
                                    .font(.ax(.subheadline, .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 118, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// Android draws the bar buttons as rounded squares, not circles.
    private func barButtonLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var backButton: some View {
        Button { dismiss() } label: { barButtonLabel("chevron.left") }
            .accessibilityLabel("Назад")
    }

    @ViewBuilder private var collectionButton: some View {
        if model?.release != nil, viewer == env.session.viewerKey {
            Button { isShowingCollectionPicker = true } label: { barButtonLabel("rectangle.stack.badge.plus") }
                .accessibilityLabel("Выбрать коллекцию")
        }
    }

    // MARK: - Comments

    private func voteInlineComment(_ comment: ReleaseComment, _ vote: CommentVote,
                                   model: ReleaseDetailViewModel) async {
        guard comment.isDeleted != true, comment.canLike != false,
              !inlineVotingIDs.contains(comment.id), viewer == env.session.viewerKey
        else { return }
        guard let account = viewer?.account else {
            env.session.promptSignIn()
            return
        }

        inlineVotingIDs.insert(comment.id)
        defer { inlineVotingIDs.remove(comment.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(
                CommentEndpoints.vote(commentID: comment.id, vote: vote),
                for: account
            )
            AppHaptics.shared.play(.voteCast)
            await model.load()
        } catch {
            if !ProfileRequestFailure.isCancellation(error) {
                inlineCommentError = Paginator<Release>.message(for: error)
                AppHaptics.shared.play(.error)
            }
        }
    }

    private func commentsSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
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
                ForEach(comments.prefix(5)) { comment in
                    CommentRow(
                        comment: comment,
                        onReply: { inlineComposer.replyingTo = ProfileComment(releaseComment: comment) },
                        onVote: { vote in
                            Task { await voteInlineComment(comment, vote, model: model) }
                        },
                        onOpenReplies: { inlineThread = comment },
                        isVoting: inlineVotingIDs.contains(comment.id),
                        actionsEnabled: !model.isPerformingAction
                    )
                        .padding(.horizontal)
                }
            } else {
                Text("Пока нет комментариев")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Android hides the composer entirely for an announced (unreleased) title.
            if release.status?.id != AiringStatus.announced.rawValue {
                CommentComposerBar(composer: inlineComposer, showsDivider: false) {
                    let location = ProfileCommentLocation(category: .releases, parentID: release.id)
                    if await inlineComposer.send(at: location, parentCommentID: inlineComposer.replyingTo?.threadRootID, session: env.session) {
                        AppHaptics.shared.play(.commentSent)
                        await model.load()
                    } else {
                        AppHaptics.shared.play(.commentFailed)
                    }
                }
                .onAppear { inlineComposer.captureViewer(env.session.viewerKey) }
            }
        }
        .navigationDestination(item: $inlineThread) { comment in
            CommentThreadView(comment: comment, releaseID: release.id, viewer: viewer)
        }
    }
}

// MARK: - Rating pieces

/// The 5..1 bars next to the average score.
struct VoteHistogram: View {
    let distribution: [(score: Int, count: Int)]

    /// Bars show each score's share of all votes, so a 4.7 release does not
    /// draw a full «5» bar next to empty ones.
    private var total: Int { max(1, distribution.reduce(0) { $0 + $1.count }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(distribution, id: \.score) { row in
                HStack(spacing: 12) {
                    Text(verbatim: String(row.score))
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 14, alignment: .trailing)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.18))
                            Capsule()
                                .fill(Color.primary.opacity(0.88))
                                .frame(width: max(geometry.size.height,
                                                  geometry.size.width * CGFloat(row.count) / CGFloat(total)))
                        }
                    }
                    .frame(height: 11)
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

/// A related release, as the Android list draws it: poster, title, then the year,
/// the score and a filled category chip; the row of the open release says «Вы здесь»
/// on the right behind a thin divider.
@MainActor
struct RelatedReleaseRow: View {
    let release: Release
    var isCurrent = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.row) {
            ReleasePoster(url: release.posterURL, width: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(release.displayTitle)
                    .font(.ax(fixed: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                FlowRow(spacing: 8) {
                    // The chip carries 4pt of vertical padding; the plain items carry
                    // the same so every item in the line is one height and aligns.
                    if let year = release.year, !year.isEmpty {
                        Text("\(year) год").font(.ax(fixed: 14)).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                    if let rating = release.ratingText {
                        HStack(spacing: 3) {
                            Text("•").foregroundStyle(.secondary)
                            Text(rating).font(.ax(fixed: 14)).foregroundStyle(.secondary)
                            Image(systemName: "star.fill").font(.ax(fixed: 12)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    if let category = release.category?.name, !category.isEmpty {
                        Text(category)
                            .font(.ax(fixed: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
            if isCurrent {
                HStack(spacing: 14) {
                    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 44)
                    Text("Вы\nздесь").font(.ax(fixed: 14)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
            }
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
