import SwiftUI
import AnixartKit

/// "Выберите вариант": the voice-over list, with the Все / Озвучки / Субтитры
/// filter, the per-variant episode count and view count, and the СУБТИТРЫ and
/// НОВИНКА badges the Android screen shows.
@MainActor
struct EpisodePickerView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false

    let release: Release
    @State private var viewer: ProfileViewerKey?
    @State private var model: EpisodePickerViewModel?
    @State private var isHintVisible = true
    @AppStorage("episodePicker.pinnedVoiceovers") private var pinnedRaw = ""
    @Namespace private var kindHighlight
    @State private var kindMotion = SelectionMotionIntent<EpisodePickerViewModel.Kind>()

    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    init(release: Release, viewer: ProfileViewerKey? = nil) {
        self.release = release
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        Group {
            if let viewer, viewer != env.session.viewerKey {
                ProfileViewerNotice(viewer: viewer)
            } else if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Выберите вариант")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model?.reload() }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .disabled(viewer != env.session.viewerKey)
            }
        }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if model == nil {
                model = EpisodePickerViewModel(release: release, session: env.session, viewer: viewer)
            }
            await model?.loadTypes()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model?.invalidate(); kindMotion.reset() }
        }
    }

    @ViewBuilder
    private func content(_ model: EpisodePickerViewModel) -> some View {
        if model.isLoadingTypes && model.types.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
        } else if model.types.isEmpty {
            StatusMessageView(
                title: "Нет доступных озвучек",
                message: model.errorMessage ?? "Для этого релиза пока нет серий",
                systemImage: "film"
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    kindChips(model)
                    Group {
                        if isHintVisible { hint }
                        if model.isCheckingPlayability {
                            Label("Проверяем, какие варианты откроются во встроенном плеере…", systemImage: "clock")
                                .font(.ax(.caption))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }

                        ForEach(pinnedFirst(model.visibleTypes)) { type in
                            NavigationLink {
                                EpisodeListView(release: release, type: type, viewer: viewer)
                            } label: {
                                typeRow(type, model: model)
                                    .overlay(alignment: .topTrailing) {
                                        if isPinned(type) {
                                            Image(systemName: "pin.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .padding(10)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            // Swipe the row to the left to pin or unpin the voice-over.
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 40)
                                    .onEnded { value in
                                        guard value.translation.width < -80,
                                              abs(value.translation.height) < 40 else { return }
                                        withAnimation { togglePin(type) }
                                    }
                            )
                            .contextMenu {
                                Button(isPinned(type) ? "Открепить" : "Закрепить",
                                       systemImage: isPinned(type) ? "pin.slash" : "pin") {
                                    withAnimation { togglePin(type) }
                                }
                            }
                            Divider().padding(.leading, 96)
                        }
                    }
                    .transaction {
                        if kindMotion.shouldAnimate(model.kind) {
                            $0.animation = nil; $0.disablesAnimations = true
                        }
                    }
                }
            }
        }
    }

    private var pinnedIDs: Set<String> { Set(pinnedRaw.split(separator: ",").map(String.init)) }
    private func isPinned(_ type: EpisodeType) -> Bool { pinnedIDs.contains("(type.id)") }

    private func togglePin(_ type: EpisodeType) {
        var ids = pinnedIDs
        if !ids.insert("(type.id)").inserted { ids.remove("(type.id)") }
        pinnedRaw = ids.sorted().joined(separator: ",")
    }

    /// Pinned voice-overs first; the server order is otherwise kept.
    private func pinnedFirst(_ types: [EpisodeType]) -> [EpisodeType] {
        types.filter(isPinned) + types.filter { !isPinned($0) }
    }

    private func kindChips(_ model: EpisodePickerViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(EpisodePickerViewModel.Kind.allCases) { kind in
                        let isSelected = model.kind == kind
                        Button { selectKind(kind, model: model) } label: {
                            SelectionLabel(title: kind.title, isSelected: isSelected, showsCheckmark: true)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background {
                                    SelectionChipBackground(isSelected: isSelected, shape: Capsule(),
                                                            color: Theme.accent.opacity(0.3), namespace: kindHighlight)
                                }
                                .foregroundStyle(.primary)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onKeyPress(.return) { selectKind(kind, model: model, fromKeyboard: true); return .handled }
                        .onKeyPress(.space) { selectKind(kind, model: model, fromKeyboard: true); return .handled }
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                        .id(kind.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, Theme.Spacing.row)
            }
            .onAppear { proxy.scrollTo(model.kind.id, anchor: .center) }
            .onChange(of: model.kind) { _, kind in
                guard kind == model.kind else { return }
                motion.perform(animated: kindMotion.shouldAnimate(kind)) { proxy.scrollTo(kind.id, anchor: .center) }
                kindMotion.complete(kind)
            }
        }
    }

    private func selectKind(_ kind: EpisodePickerViewModel.Kind, model: EpisodePickerViewModel, fromKeyboard: Bool = false) {
        guard model.hasCurrentViewer, model.kind != kind else { return }
        kindMotion.register(kind, fromKeyboard: fromKeyboard)
        motion.perform(animated: !fromKeyboard) { model.select(kind: kind) }
    }

    private func hideHint(fromKeyboard: Bool = false) {
        guard isHintVisible else { return }
        motion.perform(animated: !fromKeyboard, using: .default) { isHintVisible = false }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Напротив каждого варианта озвучки указано общее количество доступных серий. Статистика просмотров обновляется ежедневно.")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { hideHint() } label: {
                Image(systemName: "xmark.circle")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onKeyPress(.return) { hideHint(fromKeyboard: true); return .handled }
            .onKeyPress(.space) { hideHint(fromKeyboard: true); return .handled }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, Theme.Spacing.row)
    }

    private func typeRow(_ type: EpisodeType, model: EpisodePickerViewModel) -> some View {
        HStack(spacing: 14) {
            CachedAsyncImage(url: type.iconURL, maxPixelSize: 120) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "mic.fill").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(type.displayName)
                        .font(.ax(.title3))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if type.isSubtitles { badge("СУБТИТРЫ", color: .secondary) }
                    // Most voice-overs sit on a hosting that only serves its own
                    // player page; this marks the ones the built-in player can
                    // actually take, so the choice is informed.
                    if model.playableTypeIDs.contains(type.id) {
                        badge("ПЛЕЕР", color: Theme.listColor(.watching))
                    }
                    // The variant that received the release's newest episode is
                    // the one the Android picker marks as new.
                    if type.id == release.episodeLastUpdate?.lastEpisodeTypeUpdateId {
                        badge("НОВИНКА", color: Theme.newBadge)
                    }
                }
                if let count = type.episodeCountLine {
                    Text(count)
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let views = type.viewCount, views > 0 {
                HStack(spacing: 6) {
                    Text(Format.compactCount(views))
                        .font(.ax(.subheadline))
                        .monospacedDigit()
                    Image(systemName: "eye")
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.ax(fixed: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(color, lineWidth: 1))
    }
}

/// "Выберите серию": the chosen voice-over's episodes, with the hosting picker
/// and the hint card the Android screen shows above them.
@MainActor
struct EpisodeListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false

    let release: Release
    let type: EpisodeType

    @State private var viewer: ProfileViewerKey?
    @State private var model: EpisodePickerViewModel?
    @State private var launcher: EpisodeLauncher?
    @State private var isHintVisible = true
    @Namespace private var sourceHighlight
    @State private var sourceMotion = SelectionMotionIntent<Int>()
    @State private var sourceSelectionTask: Task<Void, Never>?

    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    init(release: Release, type: EpisodeType, viewer: ProfileViewerKey? = nil) {
        self.release = release
        self.type = type
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        Group {
            if let viewer, viewer != env.session.viewerKey {
                ProfileViewerNotice(viewer: viewer)
            } else if let model, let launcher {
                content(model)
                    .episodePlayback(
                        launcher,
                        releaseTitle: model.releaseTitle,
                        alternativeSourceName: model.sourceWithDirectStream.map(\.displayName),
                        onProgress: { episode, seconds in
                            Task { await model.saveProgress(for: episode, seconds: seconds) }
                        },
                        onFinished: { episode in
                            Task { await model.markWatched(episode, watched: true) }
                        }
                    )
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The Android bar carries the screen name over the source name.
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Выберите серию").font(.ax(.headline))
                    if let source = model?.selectedSource?.displayName {
                        Text("Источник \(source)")
                            .font(.ax(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model?.toggleSortOrder() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(model?.sortDescending == true ? Theme.accent : .primary)
                }
                .disabled(viewer != env.session.viewerKey)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await model?.markAllWatched() }
                    } label: {
                        Label("Отметить все просмотренными", systemImage: "checkmark.circle")
                    }
                    Button {
                        Task { await model?.markAllUnwatched() }
                    } label: {
                        Label("Снять отметки", systemImage: "xmark.circle")
                    }
                    Divider()
                    Button {
                        isHintVisible = true
                    } label: {
                        Label("Показать подсказку", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(viewer != env.session.viewerKey || model?.isUpdatingWatched == true)
            }
        }
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            if model == nil {
                let fresh = EpisodePickerViewModel(release: release, session: env.session, viewer: viewer)
                model = fresh
                launcher = EpisodeLauncher(preferences: PlaybackPreferences())
                await fresh.select(type: type)
            }
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            sourceSelectionTask?.cancel()
            sourceSelectionTask = nil
            sourceMotion.reset()
            launcher?.cancel()
            model?.invalidate()
        }
        .onDisappear { sourceMotion.reset() }
    }

    @ViewBuilder
    private func content(_ model: EpisodePickerViewModel) -> some View {
        VStack(spacing: 0) {
            if model.sources.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.sources) { source in
                                let isSelected = model.selectedSource?.id == source.id
                                Button { selectSource(source, model: model) } label: {
                                    HStack(spacing: 5) {
                                        SelectionLabel(title: source.displayName, isSelected: isSelected, style: .subheadline)
                                        // Only these can go to the built-in player.
                                        if model.hasDirectStream(source) {
                                            Image(systemName: "play.circle.fill").font(.ax(.caption))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .frame(minHeight: 44)
                                    .background {
                                        SelectionChipBackground(isSelected: isSelected, shape: Capsule(),
                                                                color: Theme.accent.opacity(0.22), namespace: sourceHighlight)
                                    }
                                    .foregroundStyle(isSelected ? Theme.accent : .primary)
                                    .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .onKeyPress(.return) { selectSource(source, model: model, fromKeyboard: true); return .handled }
                                .onKeyPress(.space) { selectSource(source, model: model, fromKeyboard: true); return .handled }
                                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                                .id(source.id)
                            }
                        }
                        // The async model owns selection/data. Animate only the
                        // strip, and only when it publishes the explicit target.
                        .animation(sourceMotion.animation(for: model.selectedSource?.id, policy: motion), value: model.selectedSource?.id)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        if let id = model.selectedSource?.id { proxy.scrollTo(id, anchor: .center) }
                    }
                    .onChange(of: model.selectedSource?.id) { _, id in
                        guard id == model.selectedSource?.id else { return }
                        if let id {
                            motion.perform(animated: sourceMotion.shouldAnimate(id)) { proxy.scrollTo(id, anchor: .center) }
                        }
                        sourceMotion.complete(id)
                    }
                }
                Divider()
            }

            if model.isLoadingEpisodes && model.episodes.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                Spacer()
            } else if model.episodes.isEmpty {
                StatusMessageView(
                    title: "Нет серий",
                    message: model.errorMessage ?? "В этом варианте пока нет серий",
                    systemImage: "film"
                )
            } else {
                List {
                    Section {
                        Text(type.displayName)
                            .font(.ax(.largeTitle, .bold))
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)

                        if isHintVisible { hint }
                    }

                    ForEach(model.episodes) { episode in
                        episodeRow(episode, model: model)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func selectSource(_ source: EpisodeSource, model: EpisodePickerViewModel, fromKeyboard: Bool = false) {
        guard model.hasCurrentViewer, model.sources.contains(where: { $0.id == source.id }), !sourceMotion.isPending(source.id),
               model.selectedSource?.id != source.id || sourceMotion.hasPendingSelection else { return }
        sourceMotion.register(source.id, fromKeyboard: fromKeyboard)
        sourceSelectionTask?.cancel()
        sourceSelectionTask = Task { await model.select(source: source) }
    }

    private func hideHint(fromKeyboard: Bool = false) {
        guard isHintVisible else { return }
        motion.perform(animated: !fromKeyboard, using: .default) { isHintVisible = false }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Если серия не запускается ни через какой видеоплеер, попробуйте сменить источник, "
                 + "если это доступно. Любая реклама в видео к приложению отношения не имеет.")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { hideHint() } label: {
                Image(systemName: "xmark.circle")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onKeyPress(.return) { hideHint(fromKeyboard: true); return .handled }
            .onKeyPress(.space) { hideHint(fromKeyboard: true); return .handled }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .listRowSeparator(.hidden)
    }

    private func episodeRow(_ episode: Episode, model: EpisodePickerViewModel) -> some View {
        HStack(spacing: 12) {
            Button {
                launcher?.open(episode)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(episode.displayName)
                            .font(.ax(.title3))
                            .foregroundStyle(episode.isWatched == true ? .secondary : .primary)
                        HStack(spacing: 8) {
                            if episode.isFiller == true {
                                Text("филлер")
                                    .font(.ax(.caption2))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.08), in: Capsule())
                            }
                            if let quality = episode.quality, quality > 0 {
                                Text("\(quality)p").font(.ax(.caption)).foregroundStyle(.secondary)
                            }
                            if episode.isEmbed {
                                Label("плеер источника", systemImage: "globe")
                                    .labelStyle(.compact)
                                    .font(.ax(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            if let resume = episode.resumePosition, resume > 1 {
                                Label(Format.duration(resume), systemImage: "arrow.clockwise")
                                    .labelStyle(.compact)
                                    .font(.ax(.caption))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if episode.isWatched == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The Android row keeps a per-episode overflow next to it.
            Menu {
                Button {
                    launcher?.open(episode)
                } label: {
                    Label("Воспроизвести", systemImage: "play")
                }
                Button {
                    Task { await model.markWatched(episode, watched: !(episode.isWatched ?? false)) }
                } label: {
                    Label(
                        episode.isWatched == true ? "Отметить непросмотренной" : "Отметить просмотренной",
                        systemImage: episode.isWatched == true ? "xmark.circle" : "checkmark.circle"
                    )
                }
                if let url = episode.playbackURL {
                    ShareLink(item: url) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await model.markWatched(episode, watched: !(episode.isWatched ?? false)) }
            } label: {
                Label(
                    episode.isWatched == true ? "Не просмотрено" : "Просмотрено",
                    systemImage: episode.isWatched == true ? "xmark.circle" : "checkmark.circle"
                )
            }
            .tint(Theme.accent)
        }
    }
}
