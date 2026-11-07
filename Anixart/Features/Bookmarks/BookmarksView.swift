import SwiftUI
import AnixartKit

/// Bookmarks tab. Tab order and titles follow `BookmarkTabsFragment` in the APK:
/// collections, history, favourites, then the five watch lists.
@MainActor
struct BookmarksView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab = BookmarkTab.defaultSelection(storageKey: UserDefaults.standard.string(forKey: DeviceAppearancePreferenceKey.defaultBookmarks))
    @AppStorage(DeviceAppearancePreferenceKey.defaultBookmarks) private var defaultTab = BookmarkTab.favorites.storageKey
    @State private var sort: BookmarkSort = .addedDescending
    @State private var isShowingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @Namespace private var tabIndicator
    @State private var selectionMotion = SelectionMotionIntent<BookmarkTab>()
    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

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

        var storageKey: String {
            switch self {
            case .collections: return "collections"
            case .history: return "history"
            case .favorites: return "favorites"
            case .list(let status): return "list.\(status.rawValue)"
            }
        }

        init?(storageKey: String) {
            guard let tab = Self.allCases.first(where: { $0.storageKey == storageKey }) else { return nil }
            self = tab
        }

        static func defaultSelection(storageKey: String?) -> BookmarkTab {
            storageKey.flatMap { BookmarkTab(storageKey: $0) } ?? .favorites
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
            VStack(spacing: 0) {
                BrowsingHeader(onSettings: { isShowingSettings = true })
                Group {
                    if env.session.isSignedIn {
                        signedInContent
                    } else {
                        SignInPromptView(
                            message: "Закладки, история и избранное привязаны к аккаунту."
                        )
                    }
                }
            }
            .navigationTitle("Закладки")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .onChange(of: defaultTab) { _, value in tab = BookmarkTab.defaultSelection(storageKey: value) }
        }
    }

    private var signedInContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(BookmarkTab.allCases, id: \.self) { candidate in
                            Button { select(candidate) } label: {
                                SelectionLabel(title: candidate.title, isSelected: tab == candidate)
                                    .foregroundStyle(tab == candidate ? Color.primary : Color.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background {
                                        SelectionChipBackground(isSelected: tab == candidate, shape: Capsule(),
                                                                color: Theme.accent.opacity(0.3), namespace: tabIndicator)
                                    }
                                    .fixedSize()
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .onKeyPress(.return) { select(candidate, fromKeyboard: true); return .handled }
                            .onKeyPress(.space) { select(candidate, fromKeyboard: true); return .handled }
                            .id(candidate)
                            .accessibilityAddTraits(tab == candidate ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear { proxy.scrollTo(tab, anchor: .center) }
                .onChange(of: tab) { _, selected in
                    guard selected == tab else { return }
                    motion.perform(animated: selectionMotion.shouldAnimate(selected)) { proxy.scrollTo(selected, anchor: .center) }
                    selectionMotion.complete(selected)
                }
            }
            if tab.supportsSorting {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(BookmarkSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Сортировка")
            }
            }
            .floatingStrip()
            ContinueWatchingCard()


            Group {
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
            .transaction {
                if selectionMotion.shouldAnimate(tab) {
                    $0.animation = nil; $0.disablesAnimations = true
                }
            }
        }
    }

    private func select(_ candidate: BookmarkTab, fromKeyboard: Bool = false) {
        guard tab != candidate else { return }
        selectionMotion.register(candidate, fromKeyboard: fromKeyboard)
        motion.perform(animated: !fromKeyboard) { tab = candidate }
    }
}

/// One paginated release list inside the bookmarks tab.
@MainActor
struct BookmarkReleaseList: View {
    @Environment(AppEnvironment.self) private var env

    enum Kind: Hashable, Sendable {
        case favorites
        case history
        case list(ProfileListStatus)
    }

    let kind: Kind
    let sort: BookmarkSort

    @State private var model: BookmarkReleaseListModel?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    private var taskID: BookmarkReleaseListKey {
        BookmarkReleaseListKey(kind: kind, sort: sort, viewer: env.session.viewerKey)
    }

    var body: some View {
        List {
            if let model, model.hasCurrentViewer, model.kind == kind, model.sort == sort {
                if let error = model.actionError {
                    Text(error).font(.ax(.subheadline)).foregroundStyle(.red)
                }
                PaginatedContent(
                    paginator: model.paginator,
                    emptyTitle: emptyTitle,
                    emptyMessage: emptyMessage
                ) { release in
                    ReleaseListRow(release: release, style: .plain, showsWatchHistory: kind == .history) { actionTarget = release }
                    .onTapGesture { opened = release }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 12))
                    .swipeActions(edge: .trailing) {
                        if case .history = kind {
                            Button("Убрать", role: .destructive) {
                                Task { await model.removeFromHistory(releaseID: release.id) }
                            }
                            .disabled(model.removingIDs.contains(release.id))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model?.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model?.viewer)
        }
        .sheet(item: $actionTarget, onDismiss: { Task { await model?.reload() } }) { release in
            if let model { ReleaseQuickActionsSheet(release: release, viewer: model.viewer) }
        }
        .task(id: taskID) {
            if model?.viewer != taskID.viewer || model?.kind != kind || model?.sort != sort {
                model = BookmarkReleaseListModel(kind: kind, sort: sort, session: env.session)
                opened = nil
                actionTarget = nil
            }
            await model?.paginator.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, _ in opened = nil; actionTarget = nil }
    }

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
            Text("Нужен аккаунт").font(.ax(.headline))
            Text(message)
                .font(.ax(.subheadline))
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
