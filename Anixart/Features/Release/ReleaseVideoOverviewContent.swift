import SwiftUI
import AnixartKit

@MainActor
struct ReleaseVideoOverviewContent: View {
    let model: ReleaseVideoOverviewModel
    let onPlay: (ReleaseVideo) -> Void
    let onInfo: (ReleaseVideo) -> Void

    var body: some View {
        if let release = model.release {
            // Beta 3: a big crop of the poster with «Видео» and the release name on it.
            Section {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: release.posterURL, maxPixelSize: 900) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Color.clear }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Видео").font(.ax(fixed: 44, .bold))
                        Text(release.displayTitle).font(.ax(.title3)).lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                        .padding(.horizontal, 16)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        Text(section.category?.name ?? "Видео").font(.ax(.title2, .bold)).textCase(nil)
                        Spacer()
                        if section.showsAll, let categoryID = section.categoryID {
                            NavigationLink("Показать все") {
                                ReleaseVideosView(release: release, categoryID: categoryID,
                                                  categoryTitle: section.category?.name, viewer: model.viewer)
                            }.font(.ax(.body, .semibold)).textCase(nil)
                        }
                    }
                    .foregroundStyle(.primary)
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

    /// 16:9 cards about 57% of the screen wide, as on Android: the title sits on the picture,
    /// and «Информация о видео» moved to the long-press menu.
    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottomLeading) {
                ReleaseVideoThumbnail(video: video, width: 224, height: 126)
                Text(video.title ?? "Видео")
                    .font(.ax(.subheadline, .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .lineLimit(1)
                    .padding(10)
            }
            .frame(width: 224, height: 126)
        }
        .buttonStyle(.plain).disabled(video.playbackURL == nil)
        .contextMenu { Button("Информация о видео", systemImage: "info.circle", action: onInfo) }
        .accessibilityLabel(video.title ?? "Видео")
        .accessibilityHint(video.playbackURL == nil ? "Ссылка на видео недоступна" : "Воспроизвести")
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
        .clipShape(RoundedRectangle(cornerRadius: min(20, height / 3), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: min(20, height / 3), style: .continuous)
            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            // The red play badge Android puts on YouTube videos.
            Image(systemName: "play.fill")
                .font(.system(size: height > 100 ? 14 : 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, height > 100 ? 12 : 7)
                .padding(.vertical, height > 100 ? 6 : 3)
                .background(Color(red: 0.9, green: 0.1, blue: 0.1), in: RoundedRectangle(cornerRadius: height > 100 ? 8 : 5, style: .continuous))
                .padding(height > 100 ? 10 : 5)
        }
    }
}
