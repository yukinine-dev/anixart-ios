import SwiftUI
import AnixartKit

/// Bookmarks tab. Tab order and titles follow `BookmarkTabsFragment` in the APK:
/// collections, history, favourites, then the five watch lists.
@MainActor
struct BookmarksView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: BookmarkTab = .list(.watching)
    @State private var sort: BookmarkSort = .addedDescending

    enum BookmarkTab: Hashable, CaseIterable {
        case collections, history, favorites
        case list(ProfileListStatus)

        static var allCases: [BookmarkTab] {
            [.collections, .history, .favorites] + ProfileListStatus.allCases.map(BookmarkTab.list)
        }

        var title: String {
            switch self {
            case .collections: return "Коллекции"
            case .history: return "История"
            case .favorites: return "Избранное"
            case .list(let status): return status.title
            }
        }

        /// Only the watch lists and favourites accept a sort order.
        var supportsSorting: Bool {
            switch self {
            case .collections, .history: return false
            case .favorites, .list: return true
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if env.session.isSignedIn {
                    signedInContent
                } else {
                    SignInPromptView(
                        message: "Закладки, история и избранное привязаны к аккаунту."
                    )
                }
            }
            .navigationTitle("Закладки")
            .toolbar {
                if env.session.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        if tab.supportsSorting {
                            Menu {
                                Picker("Сортировка", selection: $sort) {
                                    ForEach(BookmarkSort.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                    }
                }
            }
        }
    }

    private var signedInContent: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BookmarkTab.allCases, id: \.self) { candidate in
                        Button {
                            tab = candidate
                        } label: {
                            Text(candidate.title)
                                .font(.subheadline.weight(tab == candidate ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    tab == candidate ? Theme.accent.opacity(0.15) : Color.primary.opacity(0.05),
                                    in: Capsule()
                                )
                                .foregroundStyle(tab == candidate ? Theme.accent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            switch tab {
            case .collections:
                FavoriteCollectionsList()
            case .history:
                BookmarkReleaseList(kind: .history, sort: sort)
            case .favorites:
                BookmarkReleaseList(kind: .favorites, sort: sort)
            case .list(let status):
                BookmarkReleaseList(kind: .list(status), sort: sort)
            }
        }
    }
}

/// One paginated release list inside the bookmarks tab.
@MainActor
struct BookmarkReleaseList: View {
    @Environment(AppEnvironment.self) private var env

    enum Kind: Hashable {
        case favorites
        case history
        case list(ProfileListStatus)
    }

    let kind: Kind
    let sort: BookmarkSort

    @State private var paginator: Paginator<Release>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(
                    paginator: paginator,
                    emptyTitle: emptyTitle,
                    emptyMessage: emptyMessage
                ) { release in
                    NavigationLink {
                        ReleaseDetailView(releaseID: release.id, preloaded: release)
                    } label: {
                        ReleaseRow(release: release, showContinueWatching: kind == .history)
                    }
                    .swipeActions(edge: .trailing) {
                        if case .history = kind {
                            Button("Убрать", role: .destructive) {
                                Task { await removeFromHistory(release) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await paginator?.reload() }
        .task(id: taskID) {
            paginator = makePaginator()
            await paginator?.loadFirstPageIfNeeded()
        }
    }

    /// Rebuilds the list whenever the tab or the sort order changes.
    private var taskID: String { "\(kind)-\(sort.rawValue)" }

    private var emptyTitle: String {
        switch kind {
        case .favorites: return "В избранном пусто"
        case .history: return "История пуста"
        case .list(let status): return "В списке «\(status.title)» пусто"
        }
    }

    private var emptyMessage: String? {
        switch kind {
        case .favorites: return "Добавляйте сюда то, к чему захочется вернуться"
        case .history: return "Здесь появится всё, что вы смотрели"
        case .list: return "Добавьте релиз в этот список с его страницы"
        }
    }

    private func makePaginator() -> Paginator<Release> {
        let client = env.client
        let sort = self.sort
        switch kind {
        case .favorites:
            return Paginator { page in
                try await client.send(BookmarkEndpoints.favorites(page: page, sort: sort))
            }
        case .history:
            return Paginator { page in
                try await client.send(BookmarkEndpoints.history(page: page))
            }
        case .list(let status):
            return Paginator { page in
                try await client.send(BookmarkEndpoints.list(status, page: page, sort: sort))
            }
        }
    }

    private func removeFromHistory(_ release: Release) async {
        guard (try? await env.client.send(BookmarkEndpoints.removeFromHistory(releaseID: release.id))) != nil
        else { return }
        paginator?.remove(id: release.id)
    }
}

/// Prompt shown instead of content when a screen needs a session.
@MainActor
struct SignInPromptView: View {
    @Environment(AppEnvironment.self) private var env
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Нужен аккаунт").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Войти") { env.session.promptSignIn() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
