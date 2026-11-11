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
                    BookmarkReleaseList(kind: .favorites, sort: sort, sortSelection: $sort)
                case .list(let status):
                    BookmarkReleaseList(kind: .list(status), sort: sort, sortSelection: $sort)
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
    /// When set, the list header offers the sort menu (favourites and watch lists).
    var sortSelection: Binding<BookmarkSort>?

    @State private var model: BookmarkReleaseListModel?
    @State private var opened: Release?
    @State private var actionTarget: Release?

    private var taskID: BookmarkReleaseListKey {
        BookmarkReleaseListKey(kind: kind, sort: sort, viewer: env.session.viewerKey)
    }

    var body: some View {
        List {
            if let model, model.hasCurrentViewer, model.kind == kind, model.sort == sort {
                listHeader(model)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    /// «N всего», the sort pill and the shuffle button, as the Android list opens.
    private func listHeader(_ model: BookmarkReleaseListModel) -> some View {
        HStack(spacing: 12) {
            Text(model.paginator.totalCount.map { "\(Format.count($0)) всего" } ?? " ")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer(minLength: 0)
            if let sortSelection {
                Menu {
                    ForEach(BookmarkSortField.allCases) { field in
                        Menu(field.title) {
                            Picker(field.title, selection: sortSelection) {
                                ForEach(field.options) { option in Text(option.directionTitle).tag(option) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease")
                        Text(BookmarkSortField(sortSelection.wrappedValue).title).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .font(.ax(.subheadline, .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color.primary.opacity(0.09), in: Capsule())
                }
                .accessibilityLabel("Сортировка")
            }
            Button {
                if let random = model.paginator.items.randomElement() { opened = random }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .frame(width: 56, height: 44)
                    .background(Color.primary.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.paginator.items.isEmpty)
            .accessibilityLabel("Случайный релиз из списка")
        }
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

/// Android groups the eight sort orders into four fields, each with a direction.
enum BookmarkSortField: CaseIterable, Identifiable {
    case added, year, alphabet, rating
    var id: Self { self }

    init(_ sort: BookmarkSort) {
        switch sort {
        case .addedDescending, .addedAscending: self = .added
        case .releaseDateDescending, .releaseDateAscending: self = .year
        case .titleDescending, .titleAscending: self = .alphabet
        case .ratingDescending, .ratingAscending: self = .rating
        }
    }

    var title: String {
        switch self {
        case .added: return "По добавлению"
        case .year: return "По году"
        case .alphabet: return "По алфавиту"
        case .rating: return "По рейтингу"
        }
    }

    var options: [BookmarkSort] {
        switch self {
        case .added: return [.addedDescending, .addedAscending]
        case .year: return [.releaseDateDescending, .releaseDateAscending]
        case .alphabet: return [.titleDescending, .titleAscending]
        case .rating: return [.ratingDescending, .ratingAscending]
        }
    }
}

extension BookmarkSort {
    /// The direction alone, once the field is named by the submenu.
    var directionTitle: String {
        switch self {
        case .addedDescending: return "Сначала новые"
        case .addedAscending: return "Сначала старые"
        case .releaseDateDescending: return "Сначала новые"
        case .releaseDateAscending: return "Сначала старые"
        case .titleDescending: return "А–Я"
        case .titleAscending: return "Я–А"
        case .ratingDescending: return "Сначала высокий"
        case .ratingAscending: return "Сначала низкий"
        }
    }
}
