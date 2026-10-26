import SwiftUI
import AnixartKit

/// "Выберите вариант": the voice-over list, with the Все / Озвучки / Субтитры
/// filter, the per-variant episode count and view count, and the СУБТИТРЫ and
/// НОВИНКА badges the Android screen shows.
@MainActor
struct EpisodePickerView: View {
    @Environment(AppEnvironment.self) private var env

    let release: Release
    @State private var model: EpisodePickerViewModel?
    @State private var isHintVisible = true

    var body: some View {
        Group {
            if let model {
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
            }
        }
        .task {
            if model == nil {
                model = EpisodePickerViewModel(release: release, client: env.client, session: env.session)
            }
            await model?.loadTypes()
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
                    if isHintVisible { hint }
                    ForEach(model.visibleTypes) { type in
                        NavigationLink {
                            EpisodeListView(release: release, type: type)
                        } label: {
                            typeRow(type)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 96)
                    }
                }
            }
        }
    }

    private func kindChips(_ model: EpisodePickerViewModel) -> some View {
        HStack(spacing: 12) {
            ForEach(EpisodePickerViewModel.Kind.allCases) { kind in
                let isSelected = model.kind == kind
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { model.select(kind: kind) }
                } label: {
                    HStack(spacing: 8) {
                        if isSelected {
                            Image(systemName: "checkmark").font(.ax(.subheadline, .medium))
                        }
                        Text(kind.title).font(.ax(.title3))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background {
                        if isSelected {
                            Capsule().fill(Theme.accent.opacity(0.3))
                        } else {
                            Capsule().stroke(.quaternary, lineWidth: 1)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.Spacing.row)
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Напротив каждого варианта озвучки указано общее количество доступных серий. Статистика просмотров обновляется ежедневно.")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation { isHintVisible = false }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, Theme.Spacing.row)
    }

    private func typeRow(_ type: EpisodeType) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: type.iconURL) { image in
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

    let release: Release
    let type: EpisodeType

    @State private var model: EpisodePickerViewModel?
    @State private var launcher: EpisodeLauncher?
    @State private var isHintVisible = true

    var body: some View {
        Group {
            if let model, let launcher {
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
            }
        }
        .task {
            if model == nil {
                let fresh = EpisodePickerViewModel(release: release, client: env.client, session: env.session)
                model = fresh
                launcher = EpisodeLauncher(preferences: PlaybackPreferences())
                await fresh.select(type: type)
            }
        }
    }

    @ViewBuilder
    private func content(_ model: EpisodePickerViewModel) -> some View {
        VStack(spacing: 0) {
            if model.sources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.sources) { source in
                            let isSelected = model.selectedSource?.id == source.id
                            Button {
                                Task { await model.select(source: source) }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(source.displayName)
                                    // Only these can go to the built-in player.
                                    if model.hasDirectStream(source) {
                                        Image(systemName: "play.circle.fill").font(.ax(.caption))
                                    }
                                }
                                    .font(.ax(.subheadline, isSelected ? .medium : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background {
                                        if isSelected {
                                            Capsule().fill(Theme.accent.opacity(0.22))
                                        } else {
                                            Capsule().stroke(.quaternary, lineWidth: 1)
                                        }
                                    }
                                    .foregroundStyle(isSelected ? Theme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
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

    private var hint: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Если серия не запускается ни через какой видеоплеер, попробуйте сменить источник, "
                 + "если это доступно. Любая реклама в видео к приложению отношения не имеет.")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                withAnimation { isHintVisible = false }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
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
