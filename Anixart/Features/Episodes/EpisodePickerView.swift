import SwiftUI
import AnixartKit

@MainActor
struct EpisodePickerView: View {
    @Environment(AppEnvironment.self) private var env

    let release: Release
    @State private var model: EpisodePickerViewModel?
    @State private var playing: Episode?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Серии")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = EpisodePickerViewModel(release: release, client: env.client, session: env.session)
            }
            await model?.loadTypes()
        }
        .fullScreenCover(item: $playing) { episode in
            if let model {
                PlayerScreen(
                    episode: episode,
                    releaseTitle: model.releaseTitle,
                    onProgress: { seconds in
                        Task { await model.saveProgress(for: episode, seconds: seconds) }
                    },
                    onFinished: {
                        Task { await model.markWatched(episode, watched: true) }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ model: EpisodePickerViewModel) -> some View {
        if model.isLoadingTypes && model.types.isEmpty {
            ProgressView()
        } else if model.types.isEmpty {
            StatusMessageView(
                title: "Нет доступных озвучек",
                message: model.errorMessage ?? "Для этого релиза пока нет серий",
                systemImage: "film"
            )
        } else {
            List {
                Section("Озвучка") {
                    Picker("Озвучка", selection: Binding(
                        get: { model.selectedType?.id ?? model.types.first?.id ?? 0 },
                        set: { id in
                            if let type = model.types.first(where: { $0.id == id }) {
                                Task { await model.select(type: type) }
                            }
                        }
                    )) {
                        ForEach(model.types) { type in
                            Text(type.displayName).tag(type.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if model.sources.count > 1 {
                    Section("Источник") {
                        Picker("Источник", selection: Binding(
                            get: { model.selectedSource?.id ?? 0 },
                            set: { id in
                                if let source = model.sources.first(where: { $0.id == id }) {
                                    Task { await model.select(source: source) }
                                }
                            }
                        )) {
                            ForEach(model.sources) { source in
                                Text(source.displayName).tag(source.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    if model.isLoadingEpisodes {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if model.episodes.isEmpty {
                        Text("Нет серий в этом варианте")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.episodes) { episode in
                            episodeRow(episode, model: model)
                        }
                    }
                } header: {
                    HStack {
                        Text("Серии")
                        Spacer()
                        Button {
                            Task { await model.toggleSortOrder() }
                        } label: {
                            Image(systemName: model.sortDescending ? "arrow.down" : "arrow.up")
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: Episode, model: EpisodePickerViewModel) -> some View {
        Button {
            playing = episode
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.displayName)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if episode.isFiller == true {
                            Text("филлер")
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                        if let quality = episode.quality, quality > 0 {
                            Text("\(quality)p").font(.caption2).foregroundStyle(.secondary)
                        }
                        if episode.isEmbed {
                            Label("плеер источника", systemImage: "globe")
                                .labelStyle(.compact)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if episode.isWatched == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
                Image(systemName: "play.circle").foregroundStyle(.secondary)
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
