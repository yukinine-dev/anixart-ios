import AVKit
import SwiftUI

/// «Загрузки»: downloaded episodes, the queue, and the download settings.
@MainActor
struct DownloadsView: View {
    @State private var center = EpisodeDownloadCenter.shared
    @State private var playing: URL?
    @State private var confirmsClear = false
    @AppStorage(DownloadPreferenceKey.quality) private var quality = 0
    @AppStorage(DownloadPreferenceKey.wifiOnly) private var wifiOnly = true

    private var groups: [(title: String, items: [EpisodeDownloadRecord])] {
        Dictionary(grouping: center.records, by: \.releaseTitle)
            .map { (title: $0.key, items: $0.value.sorted { $0.episodeNumber < $1.episodeNumber }) }
            .sorted { $0.title < $1.title }
    }

    var body: some View {
        List {
            if center.records.isEmpty {
                ContentUnavailableView(
                    "Загрузок пока нет",
                    systemImage: "arrow.down.circle",
                    description: Text("В списке серий откройте меню ⋮ и выберите «Скачать все серии».")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { record in
                        row(record)
                    }
                }
            }
            Section("Настройки") {
                Picker("Качество", selection: $quality) {
                    Text("Наилучшее").tag(0)
                    Text("1080p").tag(1080)
                    Text("720p").tag(720)
                    Text("480p").tag(480)
                }
                Toggle("Только по Wi-Fi", isOn: $wifiOnly)
            } footer: {
                Text("Смена параметра «Только по Wi-Fi» действует после перезапуска приложения. Серии хранятся в самом приложении.")
            }
            if !center.records.isEmpty {
                Section {
                    Button("Удалить все загрузки", role: .destructive) { confirmsClear = true }
                }
            }
        }
        .navigationTitle("Загрузки")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(get: { playing != nil }, set: { if !$0 { playing = nil } })) {
            if let playing {
                VideoPlayer(player: AVPlayer(url: playing)).ignoresSafeArea()
            }
        }
        .confirmationDialog("Удалить все загрузки?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { center.deleteAll() }
            Button("Отмена", role: .cancel) { }
        }
    }

    @ViewBuilder
    private func row(_ record: EpisodeDownloadRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.episodeName).font(.ax(.subheadline, .medium))
                switch record.state {
                case .queued:
                    Text("В очереди").font(.ax(.caption)).foregroundStyle(.secondary)
                case .downloading:
                    ProgressView(value: record.progress)
                    Text("\(Int(record.progress * 100))%").font(.ax(.caption)).foregroundStyle(.secondary)
                case .finished:
                    Text("Готово").font(.ax(.caption)).foregroundStyle(.secondary)
                case .failed:
                    Text(record.message ?? "Не удалось скачать").font(.ax(.caption)).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 0)
            if record.state == .finished, let url = center.fileURL(for: record) {
                Button { playing = url } label: { Image(systemName: "play.circle.fill").font(.title2) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Смотреть \(record.episodeName)")
            } else if record.state == .queued || record.state == .downloading {
                Button { center.cancel(record) } label: { Image(systemName: "xmark.circle").font(.title2) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отменить загрузку")
            }
        }
        .swipeActions {
            Button("Удалить", role: .destructive) { center.delete(record) }
        }
    }
}
