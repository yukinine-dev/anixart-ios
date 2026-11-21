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
    @Environment(\.colorScheme) private var colorScheme
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
        // iOS 26 adds a soft translucent strip under the bar buttons once the page
        // scrolls; Android has nothing there, so switch that edge effect off.
        .modifier(HideTopScrollEdgeEffect())
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
                ToolbarItem(placement: .topBarTrailing) { menuButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { menuButton }
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
            statsRow(release)
            playBlock(release)
            actionTiles(release, model: model)
            if release.isAnnouncement || release.isDeleted == true { noteBlock(release) }

            if let description = release.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                ReleaseExpandableText(text: description, lineLimit: 3, isExpanded: $isDescriptionExpanded,
                                      onExpand: { expandDescription(fromKeyboard: $0) })
                    .padding(.horizontal)
                    .padding(.top, Theme.Spacing.section)
            }
            genres(release)
    }

    @ViewBuilder
    private func detailMiddle(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            if !release.screenshotURLs.isEmpty {
                sectionRule
                screenshots(release)
            }

            if let banners = release.videoBanners, !banners.isEmpty {
                sectionRule
                videoSection(release, banners: banners)
            }

            if !release.relatedPreviewReleases.isEmpty || release.hasMoreRelatedReleases {
                sectionRule
                relatedSection(release, releases: release.relatedPreviewReleases)
            }
    }

    @ViewBuilder
    private func detailBottom(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            AnyView(ratingsAndLists(release, model: model))

            factLines(release)

            Color.clear.frame(height: 20)

            badgesCard(release)

            collectionLinks(release)
                .padding(.top, 4)

            if let recommended = release.recommendedReleases, !recommended.isEmpty {
                recommendedCarousel(releases: recommended)
                    .padding(.vertical, 16)
                    .padding(.top, Theme.Spacing.section)
            }

            commentsSection(release, model: model)
                .padding(.top, Theme.Spacing.section)
    }

    @ViewBuilder
    private func ratingsAndLists(_ release: Release, model: ReleaseDetailViewModel) -> some View {
            // Android hides the whole rating block for an announced (unreleased) title.
            if !release.isAnnouncement {
                sectionRule
                SectionHeader(title: "Оценки и списки").padding(.bottom, Theme.Spacing.row)
                ratingSection(release, model: model)
            }

            if release.isAnnouncement {
                // An unreleased title has no bar of list statuses on Android, just how
                // many people plan to watch it.
                if let planned = release.planCount, planned > 0 {
                    sectionRule
                    plannedSection(planned)
                }
            } else if release.listDistribution.contains(where: { $0.count > 0 }) {
                listsSection(release).padding(.top, 4)
            }
    }

    /// Beta 3 drops the hairlines between sections: space alone separates them.
    private var sectionRule: some View {
        Color.clear.frame(height: Theme.Spacing.section)
    }

    /// Three columns under the title: rating, episodes and season, split by hairlines.
    @ViewBuilder
    private func statsRow(_ release: Release) -> some View {
        let columns = statColumns(for: release)
        if !columns.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    VStack(spacing: 4) {
                        Text(column.value).font(.ax(.title3, .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(column.caption).font(.ax(.footnote)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    if index < columns.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 44)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.section)
        }
    }

    private func statColumns(for release: Release) -> [(value: String, caption: String)] {
        var columns: [(value: String, caption: String)] = []
        if !release.isAnnouncement, let rating = release.ratingText {
            columns.append((rating.replacingOccurrences(of: ".", with: ",") + " ★",
                            Format.count(release.voteCount) + " оценок"))
        }
        let released = release.episodesReleased
        let total = release.episodesTotal
        if released != nil || total != nil {
            let value: String
            if let released, let total, released != total { value = "\(released) из \(total)" }
            else if let total { value = "\(total)" }
            else if let released { value = "\(released)" }
            else { value = "?" }
            let minutes = (release.duration ?? 0) > 0 ? " по \(release.duration ?? 0) мин" : ""
            columns.append((value, "эп.\(minutes)"))
        }
        if let season = release.seasonAndYear {
            let caption = [release.categoryBadgeText, release.statusBadgeText]
                .compactMap { $0?.lowercased() }.joined(separator: " · ")
            columns.append((Self.capitalizingFirst(season), caption))
        }
        return columns
    }

    /// «осень 2026» -> «Осень 2026».
    private static func capitalizingFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Action tiles

    /// «В список», bookmarks, comments and «В коллекцию» as four equal tiles.
    private func actionTiles(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        let isFavorite = release.isFavorite ?? false
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            Button { isShowingListPicker = true } label: {
                tileLabel(icon: release.listStatus == nil ? "plus" : "checkmark",
                          title: release.listStatus?.title ?? "В список",
                          color: release.listStatus.map { Theme.listColor($0) })
            }
            .buttonStyle(.plain)
            .disabled(model.isPerformingAction)

            Button { Task { await model.toggleFavorite() } } label: {
                VStack(spacing: 8) {
                    BookmarkIcon(isFilled: isFavorite)
                        .frame(width: 22, height: 24)
                        // A quick squash, a pop past full size, then a bouncy settle.
                        .keyframeAnimator(initialValue: 1.0, trigger: isFavorite) { view, scale in
                            view.scaleEffect(scale)
                        } keyframes: { _ in
                            SpringKeyframe(0.7, duration: 0.1)
                            SpringKeyframe(1.5, duration: 0.2, spring: .snappy)
                            SpringKeyframe(1.0, spring: .bouncy)
                        }
                    Text(Format.exact(release.favoriteCount))
                        .font(.ax(.subheadline, .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .foregroundStyle(isFavorite ? Theme.favoriteYellow : .primary)
                .animation(.easeOut(duration: 0.25), value: isFavorite)
                .animation(.default, value: release.favoriteCount)
            }
            .buttonStyle(.plain)
            .disabled(model.isPerformingAction)

            NavigationLink {
                CommentsView(releaseID: release.id, releaseTitle: release.displayTitle, viewer: viewer)
            } label: {
                tileLabel(icon: "bubble.left.and.text.bubble.right", title: Format.exact(release.commentCount), color: nil)
            }
            .buttonStyle(.plain)

            Button { isShowingCollectionPicker = true } label: {
                tileLabel(icon: "rectangle.stack.badge.plus", title: "В коллекцию", color: nil)
            }
            .buttonStyle(.plain)
            .disabled(viewer != env.session.viewerKey)
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.row)
    }

    private func tileLabel(icon: String, title: String, color: Color?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.ax(.title3))
            Text(title).font(.ax(.footnote, .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(color ?? .primary)
    }

    // MARK: - Play

    @ViewBuilder
    private func playBlock(_ release: Release) -> some View {
        // Beta 3 puts the licensing note in the panel under the play button.
        let note = release.isDeleted == true ? nil : Self.plainNote(release)
        // Without a note the panel shows the newest episode: «Новая  8 серия · AnimeVost (Kodik)».
        let update = (release.isDeleted == true || note != nil) ? nil : Self.episodeUpdate(release)
        let caption: String? = (release.isDeleted == true || update != nil) ? nil : (note ?? release.continueWatchingText)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                if release.isDeleted == true {
                    Label("Релиз удалён", systemImage: "exclamationmark.triangle")
                        .font(.ax(.headline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                } else if release.isAnnouncement {
                    // Android swaps the play button for an inert season pill.
                    Text(release.announcementPillText)
                        .font(.ax(.headline, .semibold))
                        .tracking(1.5)
                        .foregroundStyle(palette.text.color.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        // Measured on Android: left #4D485D to right #8C869F, i.e. the
                        // lavender accent at ~33% rising to ~60%.
                        .background(LinearGradient(colors: [palette.accent.color.opacity(0.33), palette.accent.color.opacity(0.6)],
                                                   startPoint: .leading, endPoint: .trailing), in: Capsule())
                        .accessibilityLabel("Выйдет: \(release.announcementPillText.lowercased())")
                } else {
                    ReleasePlaybackButton(release: release, viewer: viewer)
                        .zIndex(1)
                }
                // Android tucks the caption into a dark panel under the button.
                if let caption {
                    Text(caption)
                        .font(.ax(.subheadline))
                        .foregroundStyle(.primary.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 34)
                        .padding(.bottom, 14)
                        .background(Color.primary.opacity(0.08),
                                    in: UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                        .padding(.top, -24)
                } else if let update {
                    HStack(spacing: 8) {
                        if update.isNew {
                            Text("Новая")
                                .font(.ax(.caption, .semibold))
                                .foregroundStyle(palette.background.color)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(palette.text.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Text(update.text).font(.ax(.footnote)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 30)
                    .padding(.bottom, 8)
                    .background(Color.primary.opacity(0.08),
                                in: UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                    .padding(.top, -24)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, Theme.Spacing.section)
    }

    /// «8 серия · AnimeVost (Kodik)». The «Новая» chip is shown for updates up to a week old;
    /// that cutoff is a guess from one Android screenshot, the real rule is not in the decompile.
    private static func episodeUpdate(_ release: Release) -> (text: String, isNew: Bool)? {
        guard let update = release.episodeLastUpdate,
              let episode = update.lastEpisodeUpdateName, !episode.isEmpty else { return nil }
        var text = episode
        if let type = update.lastEpisodeTypeUpdateName, !type.isEmpty {
            text += " · " + type
            if let source = update.lastEpisodeSourceUpdateName, !source.isEmpty { text += " (\(source))" }
        }
        let isNew = (update.lastEpisodeUpdateDate).map { Date().timeIntervalSince1970 - TimeInterval($0) < 7 * 86_400 } ?? false
        return (text, isNew)
    }

    /// The release note without its HTML, or nil when there is none.
    private static func plainNote(_ release: Release) -> String? {
        let text = release.note?
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// The server-supplied note («Премьера в апреле…»), in its own panel. It comes
    /// with per-theme colors; the plain surface is the fallback when they are absent.
    @ViewBuilder
    private func noteBlock(_ release: Release) -> some View {
        if let note = release.note?
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            // Licensing and similar notices arrive as small HTML (<b>…</b>): keep the words only.
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            let isDark = colorScheme == .dark
            let background = Self.noteColor(isDark ? release.noteBackgroundColorDark : release.noteBackgroundColorLight)
            let foreground = Self.noteColor(isDark ? release.noteTextColorDark : release.noteTextColorLight)
            Text(note)
                .font(.ax(.body))
                .foregroundStyle(foreground ?? .primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(background ?? Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.row)
        }
    }

    /// "#RRGGBB" or Android-style "#AARRGGBB".
    private static func noteColor(_ hex: String?) -> Color? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard let value = UInt32(text, radix: 16) else { return nil }
        switch text.count {
        case 6:
            return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        case 8:
            return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255, opacity: Double((value >> 24) & 0xFF) / 255)
        default: return nil
        }
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
            barButtonLabel("ellipsis").rotationEffect(.degrees(90))
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Действия с релизом")
        .disabled(viewer != env.session.viewerKey)
    }

    // MARK: - Details

    /// «Подробности»: one rounded card per fact, label left and value right.
    @ViewBuilder
    private func factLines(_ release: Release) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "Подробности")
            VStack(spacing: 4) {
                if let country = release.country, !country.isEmpty {
                    detailRow("Страна") {
                        HStack(spacing: 8) {
                            if let flag = release.countryFlag { Text(flag) }
                            Text(country)
                        }
                    }
                }
                if let season = release.seasonAndYear {
                    detailRow("Сезон") { Text(season) }
                }
                if let line = release.episodesAndDurationLine {
                    detailRow("Эпизоды") { Text(line) }
                }
                if let line = release.broadcastLine {
                    detailRow("Выход") { Text(line) }
                }
                ForEach(Self.detailCredits(for: release), id: \.value) { credit in
                    detailRow(credit.rowTitle) {
                        if let viewer {
                            NavigationLink {
                                SourceMaterialSearchView(query: credit.value, scope: credit.scope,
                                                         title: "\(credit.title): \(credit.value)", viewer: viewer)
                            } label: {
                                Text(credit.value).dashedUnderline()
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(credit.value)
                        }
                    }
                }
                if let source = release.sourceMaterialName {
                    detailRow("Первоисточник") {
                        if let viewer {
                            NavigationLink { SourceMaterialSearchView(query: source, scope: .sourceMaterial, title: source, viewer: viewer) } label: {
                                Text(source).dashedUnderline()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Первоисточник: \(source)")
                        } else {
                            Text(source)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, Theme.Spacing.section)
    }

    private func detailRow<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.ax(.title3)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value().font(.ax(.title3)).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Studio, director and original author, in the order the beta lists them.
    private static func detailCredits(for release: Release) -> [(rowTitle: String, title: String, value: String, scope: SearchScope)] {
        let entries = ReleaseCredit.entries(for: release)
        let order: [(SearchScope, String)] = [(.studio, "Студия"), (.director, "Режиссёр"), (.author, "Автор оригинала")]
        return order.compactMap { scope, rowTitle in
            entries.first { $0.scope == scope }.map { (rowTitle, $0.title, $0.value, $0.scope) }
        }
    }

    // MARK: - Genres and description

    @ViewBuilder
    private func genres(_ release: Release) -> some View {
        let list = release.genreList
        if !list.isEmpty {
            // Beta 3 shows genres as outlined chips.
            FlowRow(spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, genre in
                    NavigationLink {
                        GenreReleasesView(genres: [genre], viewer: viewer)
                    } label: {
                        Text(genre)
                            .font(.ax(.body))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, Theme.Spacing.row)
        }
    }

    private func expandDescription(fromKeyboard: Bool = false) {
        guard !isDescriptionExpanded else { return }
        motion.perform(animated: !fromKeyboard, using: .default) { isDescriptionExpanded = true }
    }

    // MARK: - Video

    private func videoSection(_ release: Release, banners: [ReleaseVideoBanner]) -> some View {
        // «Видео» with «Показать все», and the categories (trailers, previews, openings,
        // endings) as a two-column grid of picture tiles.
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            HStack {
                Text("Видео").font(.ax(.title2, .bold))
                Spacer()
                NavigationLink {
                    ReleaseVideosView(release: release, viewer: viewer)
                } label: {
                    Text("Показать все").font(.ax(.body, .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // With an odd number of categories the first one (the trailer) takes the whole
            // row and the rest pair up beneath it, as on Android.
            let leading = banners.count % 2 == 1 ? 1 : 0
            VStack(spacing: 10) {
                if leading == 1 { videoBanner(banners[0], release: release) }
                ForEach(Array(stride(from: leading, to: banners.count, by: 2)), id: \.self) { index in
                    HStack(spacing: 10) {
                        videoBanner(banners[index], release: release)
                        if index + 1 < banners.count { videoBanner(banners[index + 1], release: release) }
                    }
                }
            }
            .padding(.horizontal)
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
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                CachedAsyncImage(url: AnixartURL.image(banner.image), maxPixelSize: 900) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Rectangle().fill(.quaternary) }
                // A shade only along the bottom, where the label sits, so the picture
                // itself stays bright as on Android.
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                }
            }
            .overlay(alignment: .topTrailing) {
                if banner.isNew == true {
                    Text("Новое")
                        .font(.ax(.subheadline, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color(red: 0.78, green: 0.31, blue: 0.27), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.ax(.subheadline))
                    Text(banner.name ?? "Видео").font(.ax(.title3, .semibold)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5))
    }

    // MARK: - Rating

    private func ratingSection(_ release: Release, model: ReleaseDetailViewModel) -> some View {
        // Beta 3 groups «Оценки и списки» as stacked rounded cards under one heading.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: 2) {
                    ratingNumber(release)
                    Text(Plural.votes(release.voteCount ?? 0))
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                }

                VoteHistogram(distribution: release.voteDistribution)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
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
        // An airing release has no «Просмотрено» on Android (assumed from two ongoing titles: its count
        // exists on the server but is not drawn), so it is dropped from the bar and the legend.
        let isAiring = release.resolvedStatusId == AiringStatus.ongoing.rawValue
        let distribution = release.listDistribution.filter { !(isAiring && $0.status == .completed) }
        let total = max(1, distribution.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            HStack {
                Text("В списках у людей").font(.ax(.title3, .semibold))
                Spacer()
                Text(Format.count(distribution.reduce(0) { $0 + $1.count })).font(.ax(.title3)).foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                // Lists under 1% are not drawn (they stay in the legend), as on Android.
                let slices = distribution.filter { $0.count * 100 >= total }
                let widths = Self.segmentWidths(counts: slices.map(\.count), available: geometry.size.width, gap: 2, minWidth: 0)
                HStack(spacing: 2) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                        Rectangle()
                            .fill(Theme.listColor(slice.status))
                            .frame(width: widths[index])
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)

            // Android lays the legend out in two columns: watching, planned and
            // completed on the left; on hold and dropped on the right.
            let counts = distribution.reduce(into: [ProfileListStatus: Int]()) { $0[$1.status] = $1.count }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 9) {
                GridRow { legendItem(.watching, counts); legendItem(.holdOn, counts) }
                GridRow { legendItem(.plan, counts); legendItem(.dropped, counts) }
                GridRow { legendItem(.completed, counts); Color.clear.frame(width: 1, height: 1) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal)
    }

    /// Proportional segment widths with a floor: segments under `minWidth` are raised to it
    /// and the others give up the difference, so the bar still fills `available` exactly.
    static func segmentWidths(counts: [Int], available: CGFloat, gap: CGFloat, minWidth: CGFloat) -> [CGFloat] {
        guard !counts.isEmpty else { return [] }
        let usable = max(0, available - gap * CGFloat(counts.count - 1))
        let total = CGFloat(max(1, counts.reduce(0, +)))
        var widths = counts.map { usable * CGFloat($0) / total }
        let floored = widths.indices.filter { widths[$0] < minWidth }
        guard !floored.isEmpty, floored.count < widths.count else { return widths }
        let deficit = floored.reduce(CGFloat(0)) { $0 + (minWidth - widths[$1]) }
        let donorTotal = widths.indices.filter { !floored.contains($0) }.reduce(CGFloat(0)) { $0 + widths[$1] }
        for index in widths.indices {
            if floored.contains(index) { widths[index] = minWidth }
            else if donorTotal > 0 { widths[index] -= deficit * widths[index] / donorTotal }
        }
        return widths.map { max(0, $0) }
    }

    /// «31 145 пользователей планируют смотреть этот релиз» with the ticking clock.
    private func plannedSection(_ planned: Int) -> some View {
        let verb = Self.plannedVerb(planned)
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            SectionHeader(title: "В списках у людей")
            HStack(spacing: 14) {
                TickingClock().frame(width: 34, height: 34).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(Format.exact(planned)) \(verb.noun) \(verb.verb)")
                        .font(.ax(.subheadline))
                        .foregroundStyle(palette.accent.color)
                        .contentTransition(.numericText())
                        .animation(.default, value: planned)
                    Text("смотреть этот релиз")
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)
        }
    }

    private static func plannedVerb(_ count: Int) -> (noun: String, verb: String) {
        let tens = count % 100, ones = count % 10
        if (11...14).contains(tens) { return ("пользователей", "планируют") }
        switch ones {
        case 1: return ("пользователь", "планирует")
        case 2...4: return ("пользователя", "планируют")
        default: return ("пользователей", "планируют")
        }
    }

    @ViewBuilder
    private func legendItem(_ status: ProfileListStatus, _ counts: [ProfileListStatus: Int]) -> some View {
        if let count = counts[status], count > 0 {
            HStack(spacing: 8) {
                Circle().fill(Theme.listColor(status)).frame(width: 13, height: 13)
                Text(status.title).font(.ax(fixed: 14.5)).foregroundStyle(.secondary).lineLimit(1)
                Text(Format.count(count)).font(.ax(fixed: 14.5, .semibold)).monospacedDigit().lineLimit(1)
            }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    // MARK: - Screenshots, related, collections, recommendations

    private func screenshots(_ release: Release) -> some View {
        let urls = release.screenshotURLs
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            countHeader("Кадры", count: urls.count)
            // Wide cards that snap one at a time, with the next one peeking in.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                        Button {
                            guard let viewer, viewer == env.session.viewerKey else { return }
                            screenshotGallery = ReleaseScreenshotPresentation(urls: urls, initialIndex: index, viewer: viewer)
                        } label: {
                            Color.clear
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                .overlay {
                                    CachedAsyncImage(url: url, maxPixelSize: 640) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .containerRelativeFrame(.horizontal) { width, _ in width * 0.63 }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть кадр \(index + 1) из \(urls.count)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    /// «Франшиза N»: the first parts on a timeline inside one rounded card, with a
    /// «Все N частей» row when the franchise is longer.
    private func relatedSection(_ release: Release, releases: [Release]) -> some View {
        let total = [release.relatedCount, release.related?.releaseCount].compactMap { $0 }.max() ?? releases.count
        return VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            countHeader("Франшиза", count: total)
            VStack(spacing: 0) {
                ForEach(releases) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.id == release.id ? Theme.accent : Color.primary.opacity(0.45))
                            .frame(width: 14, height: 14)
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
                    .padding(.vertical, 12)
                }
                if release.hasMoreRelatedReleases, let related = release.related {
                    NavigationLink {
                        RelatedReleasesView(related: related, viewer: viewer, context: .release(release.id))
                    } label: {
                        HStack {
                            Text("Все \(total) частей").font(.ax(.title3, .semibold))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(.leading, 26)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 2)
                    .padding(.leading, 27).padding(.vertical, 36)
            }
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// A section title with the item count in a small rounded chip.
    private func countHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.ax(.title2, .bold))
            Text("\(count)")
                .font(.ax(.subheadline, .medium)).foregroundStyle(.secondary).monospacedDigit()
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }

    /// «Значки N»: badges earned for the release, a preview of the first few icons.
    @ViewBuilder
    private func badgesCard(_ release: Release) -> some View {
        if let count = release.badgeCount, count > 0, let viewer {
            NavigationLink {
                ReleaseBadgesView(releaseID: release.id, viewer: viewer)
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Значки").font(.ax(.title3, .semibold))
                        Text(count == 1 ? "1 значок" : "\(count) значков").font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach((release.badgesPreview ?? []).prefix(3)) { badge in
                        CachedAsyncImage(url: AnixartURL.image(badge.imageSmallUrl ?? badge.badgeUrl), maxPixelSize: 120) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { Color.clear }
                        .frame(width: 40, height: 40)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }

    private func collectionLinks(_ release: Release) -> some View {
        // Beta 3: two rounded cards, «В коллекциях N коллекций» and «Добавить в свою коллекцию».
        VStack(spacing: 4) {
            NavigationLink {
                ReleaseCollectionsView(releaseID: release.id, title: release.displayTitle, viewer: viewer)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("В коллекциях").font(.ax(.title3, .semibold))
                        if let count = release.collectionCount, count > 0 {
                            Text(Plural.collections(count)).font(.ax(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                isShowingCollectionPicker = true
            } label: {
                HStack {
                    Text("Добавить в свою коллекцию").font(.ax(.title3, .semibold))
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal)
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
                                // «★ 4,9 · Сериал», as under the cards on Android.
                                let meta = [item.ratingText.map { "★ " + $0.replacingOccurrences(of: ".", with: ",") },
                                            item.categoryBadgeText].compactMap { $0 }.joined(separator: " · ")
                                if !meta.isEmpty {
                                    Text(meta).font(.ax(.footnote)).foregroundStyle(.secondary)
                                        .lineLimit(1).frame(width: 118, alignment: .leading)
                                }
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

    /// Beta 3 moves the share/report menu to the top right, and «В коллекцию» to a tile.
    @ViewBuilder private var menuButton: some View {
        if let release = model?.release, viewer == env.session.viewerKey {
            releaseMenu(release)
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
            if !release.isAnnouncement {
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

private struct HideTopScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The clock beside «пользователей планируют»: a face with a minute hand that
/// sweeps round and a fixed hour hand.
struct TickingClock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let minute = t.truncatingRemainder(dividingBy: 6) / 6 * 360    // one lap every 6 seconds
            ZStack {
                Circle().stroke(Color.secondary, lineWidth: 2.5)
                // The hour hand stays put; only the minute hand moves.
                Capsule().fill(Color.secondary).frame(width: 2.5, height: 10)
                    .offset(y: -5).rotationEffect(.degrees(-30))
                Capsule().fill(Color.secondary).frame(width: 2.5, height: 13)
                    .offset(y: -6.5).rotationEffect(.degrees(minute))
            }
        }
    }
}

/// Wraps its children onto as many lines as they need, each child centred on
/// its line so items of different heights (text next to a chip) share a midline.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    private struct Line { var items: [(index: Int, size: CGSize)] = []; var height: CGFloat = 0 }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var result: [Line] = [Line()]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                result.append(Line())
                x = 0
            }
            result[result.count - 1].items.append((index, size))
            result[result.count - 1].height = max(result[result.count - 1].height, size.height)
            x += size.width + spacing
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = lines(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let natural = rows.map { $0.items.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, $0.items.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width ?? natural, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += line.height + spacing
        }
    }
}
