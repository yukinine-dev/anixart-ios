import SwiftUI
import AnixartKit

/// Notification feed. Entries are polymorphic, so each kind renders its own row and
/// an unrecognised kind degrades to a plain line rather than disappearing.
@MainActor
struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var paginator: Paginator<AnixartNotification>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: "Уведомлений нет",
                    emptyMessage: "Здесь появятся новые серии и заявки в друзья"
                ) { notification in
                    row(notification)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Уведомления")
        .refreshable { await paginator?.reload() }
        .task {
            if paginator == nil {
                let client = env.client
                paginator = Paginator { page in
                    try await client.send(NotificationEndpoints.all(page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
            await markRead()
        }
    }

    @ViewBuilder
    private func row(_ notification: AnixartNotification) -> some View {
        switch notification {
        case .episode(let item):
            NavigationLink {
                if let releaseID = item.episode?.release?.id {
                    ReleaseDetailView(releaseID: releaseID)
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
                    ReleaseDetailView(releaseID: releaseID)
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
                    ProfileView(profileID: profileID)
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

    private func markRead() async {
        guard env.session.isSignedIn else { return }
        _ = try? await env.client.send(NotificationEndpoints.markAllRead())
        env.session.clearNotificationBadge()
    }
}
