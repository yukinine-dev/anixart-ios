import SwiftUI
import AnixartKit

@MainActor
struct ReleaseVideoOverviewContent: View {
    let model: ReleaseVideoOverviewModel
    let onPlay: (ReleaseVideo) -> Void
    let onInfo: (ReleaseVideo) -> Void

    var body: some View {
        if let release = model.release {
            Section {
                HStack(spacing: 16) {
                    ReleasePoster(url: release.posterURL, width: 56)
                    Text(release.displayTitle).font(.ax(.title3, .medium))
                }
            }
            if !model.streamingPlatforms.isEmpty {
                Section("Онлайн просмотр") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(model.streamingPlatforms) { platform in
                                if let url = platform.destinationURL {
                                    Link(destination: url) { platformLabel(platform) }
                                } else { platformLabel(platform).accessibilityHint("Ссылка недоступна") }
                            }
                        }
                    }
                }
            }
            ForEach(model.sections) { section in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(section.videos) { video in
                                ReleaseVideoTile(video: video, onPlay: { onPlay(video) }, onInfo: { onInfo(video) })
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(section.category?.name ?? "Видео").font(.ax(.headline))
                        Spacer()
                        if section.showsAll, let categoryID = section.categoryID {
                            NavigationLink("Показать все") {
                                ReleaseVideosView(release: release, categoryID: categoryID,
                                                  categoryTitle: section.category?.name, viewer: model.viewer)
                            }.font(.ax(.subheadline))
                        }
                    }
                }
            }
            Section("Последние видео") {
                ForEach(model.videos) { video in
                    ReleaseVideoListEntry(video: video, onPlay: { onPlay(video) }, onInfo: { onInfo(video) })
                        .onAppear {
                            if video.id == model.videos.last?.id { Task { await model.loadNextPage() } }
                        }
                }
                if model.state == .loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if let error = model.errorMessage {
                    StatusMessageView(title: model.failedPage == 0 ? "Не удалось обновить видео" : "Не удалось загрузить следующую страницу",
                                      message: error, systemImage: "wifi.exclamationmark", retry: { await model.retry() })
                } else if model.videos.isEmpty { Text("Видео пока нет").font(.ax(.subheadline)).foregroundStyle(.secondary) }
            }
        } else if let error = model.errorMessage {
            StatusMessageView(title: "Не удалось загрузить видео", message: error,
                              systemImage: "wifi.exclamationmark", retry: { await model.retry() })
        } else { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40) }
    }

    private func platformLabel(_ platform: ReleaseStreamingPlatform) -> some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: AnixartURL.image(platform.icon), maxPixelSize: 40) { $0.resizable().scaledToFit() } placeholder: {
                Image(systemName: "play.rectangle")
            }.frame(width: 28, height: 28)
            Text(platform.name ?? "Сервис").font(.ax(.subheadline, .medium))
        }
        .foregroundStyle(.primary)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

@MainActor
struct ReleaseVideoListEntry: View {
    let video: ReleaseVideo
    let onPlay: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: Theme.Spacing.row) {
                    ReleaseVideoThumbnail(video: video, width: 112, height: 63)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title ?? "Видео").font(.ax(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                        if let category = video.category?.name { Text(category).font(.ax(.caption)).foregroundStyle(.secondary) }
                        if let author = video.profile { Text(author.displayLogin).font(.ax(.caption)).foregroundStyle(.secondary) }
                        if let timestamp = video.timestamp { Text(ProfileDate.text(timestamp)).font(.ax(.caption)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain).disabled(video.playbackURL == nil)
            .accessibilityHint(video.playbackURL == nil ? "Ссылка на видео недоступна" : "")
            Button(action: onInfo) { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("Информация о видео")
        }
    }
}

@MainActor
private struct ReleaseVideoTile: View {
    let video: ReleaseVideo
    let onPlay: () -> Void
    let onInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onPlay) { ReleaseVideoThumbnail(video: video, width: 260, height: 146) }
                .buttonStyle(.plain).disabled(video.playbackURL == nil)
                .accessibilityLabel(video.title ?? "Видео")
                .accessibilityHint(video.playbackURL == nil ? "Ссылка на видео недоступна" : "Воспроизвести")
            HStack(alignment: .top) {
                Text(video.title ?? "Видео").font(.ax(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 0)
                Button(action: onInfo) { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Информация о видео")
            }
        }
        .frame(width: 260, alignment: .leading)
    }
}

@MainActor
private struct ReleaseVideoThumbnail: View {
    let video: ReleaseVideo
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        CachedAsyncImage(url: AnixartURL.image(video.image), maxPixelSize: width) { image in
            image.resizable().scaledToFill()
        } placeholder: { Rectangle().fill(.quaternary) }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 3) }
    }
}
