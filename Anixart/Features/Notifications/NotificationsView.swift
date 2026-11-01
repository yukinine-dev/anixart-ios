import SwiftUI
import AnixartKit

/// Notification feed. Entries are polymorphic, so each kind renders its own row and
/// an unrecognised kind degrades to a plain line rather than disappearing.
@MainActor
struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = NotificationsModel()

    var body: some View {
        List {
            ProfileViewerNotice(viewer: model.viewer)
            if !env.session.isSignedIn {
                if env.session.state == .loading { ProgressView().frame(maxWidth: .infinity) }
                else { SignInPromptView(message: "Войдите, чтобы просматривать уведомления.") }
            }
            if model.viewer == env.session.viewerKey, let paginator = model.paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Уведомлений нет",
                    emptyMessage: "Здесь появятся новые серии и заявки в друзья"
                ) { notification in
                    row(notification)
                }
                if let error = model.readError {
                    StatusMessageView(title: "Не удалось отметить уведомления прочитанными", message: error,
                                      retry: { await model.retryRead(session: env.session) })
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Уведомления")
        .refreshable { await model.paginator?.reload() }
        .task(id: model.filter) { await model.load(session: env.session) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Тип уведомлений", selection: $model.filter) {
                        ForEach(NotificationFeedFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ProfileNotificationPreferencesView(account: model.viewer?.account ?? env.session.accountKey) } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task(id: model.readCandidates) { await model.markReadIfNeeded(session: env.session) }
        .onChange(of: env.session.viewerKey) { _, current in model.invalidate(for: current) }
    }

    @ViewBuilder
    private func row(_ notification: AnixartNotification) -> some View {
        switch notification {
        case .episode(let item):
            NavigationLink {
                if let releaseID = item.episode?.release?.id {
                    ReleaseDetailView(releaseID: releaseID, viewer: model.viewer)
                }
            } label: {
                notificationBody(
                    title: item.episode?.release?.titleRu ?? "Новая серия",
                    subtitle: [item.episode?.name, item.episode?.source?.type?.name]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    imageURL: AnixartURL.image(item.episode?.release?.image),
                    systemImage: "film",
                    date: item.base.date,
                    isNew: item.base.isNew ?? false
                )
            }

        case .relatedRelease(let item):
            NavigationLink {
                if let releaseID = item.release?.id {
                    ReleaseDetailView(releaseID: releaseID, viewer: model.viewer)
                }
            } label: {
                notificationBody(
                    title: item.release?.titleRu ?? "Новый релиз",
                    subtitle: "Добавлено в знакомую вам франшизу",
                    imageURL: AnixartURL.image(item.release?.image),
                    systemImage: "rectangle.stack",
                    date: item.base.date,
                    isNew: item.base.isNew ?? false
                )
            }

        case .friend(let item):
            NavigationLink {
                if let profileID = item.byProfile?.id {
                    ProfileView(profileID: profileID, viewer: model.viewer)
                }
            } label: {
                notificationBody(
                    title: item.byProfile?.login ?? "Заявка в друзья",
                    subtitle: "Активность в друзьях",
                    imageURL: AnixartURL.image(item.byProfile?.avatar),
                    systemImage: "person.2",
                    date: item.base.date,
                    isNew: item.base.isNew ?? false
                )
            }

        case .article(let item):
            NavigationLink {
                if let id = item.article?.id { ProfileArticleView(articleID: id, preloaded: item.article?.value, viewer: model.viewer) }
            } label: {
                notificationBody(title: item.article?.value?.channel?.title ?? "Новая запись", subtitle: "Запись блога или канала",
                                 imageURL: AnixartURL.image(item.article?.value?.channel?.avatar), systemImage: "doc.text",
                                 date: item.base.date, isNew: item.base.isNew == true)
            }
        case .comment(let item):
            NavigationLink {
                if let id = item.comment?.id {
                    ProfileCommentDetailView(commentID: id, category: item.category, preloaded: item.comment?.value,
                                             fallbackLocation: item.parentComment?.value?.location, viewer: model.viewer)
                }
            } label: {
                notificationBody(title: item.comment?.value?.profile?.login ?? "Комментарий",
                                 subtitle: item.comment?.value?.message ?? "Новый комментарий или ответ",
                                 imageURL: AnixartURL.image(item.comment?.value?.profile?.avatar), systemImage: "bubble.left",
                                 date: item.base.date, isNew: item.base.isNew == true)
            }
        case .unsupported(let item):
            notificationBody(
                title: "Уведомление",
                subtitle: "Этот тип пока не поддерживается приложением",
                imageURL: nil,
                systemImage: "bell",
                date: item.date,
                isNew: item.isNew ?? false
            )
        }
    }

    private func notificationBody(
        title: String,
        subtitle: String,
        imageURL: URL?,
        systemImage: String,
        date: Date?,
        isNew: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.row) {
            if let imageURL {
                CachedAsyncImage(url: imageURL, maxPixelSize: 120) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 44, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: systemImage)
                    .frame(width: 44, height: 58)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ax(.subheadline, .medium)).lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.ax(.caption)).foregroundStyle(.secondary).lineLimit(2)
                }
                if let relative = Format.relativeDate(date) {
                    Text(relative).font(.ax(.caption2)).foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if isNew {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.top, 6)
            }
        }
    }

}
