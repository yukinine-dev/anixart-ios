import SwiftUI
import AnixartKit

/// Главная: a search field and the notification / settings buttons, a scrollable strip
/// of tabs, and the selected tab's release list underneath.
@MainActor
struct HomeView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var preferences = HomePreferences()
    @State private var selection: HomeTab?
    @State private var isShowingSettings = false
    @State private var isShowingSearch = false
    @State private var isShowingTabSettings = false
    @State private var isShowingDefaultTab = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    @Namespace private var tabIndicator
    @State private var selectionMotion = SelectionMotionIntent<HomeTab>()
    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                tabStrip.floatingStrip()
                ContinueWatchingCard()

                Group {
                    switch selection ?? preferences.defaultTab {
                    case .custom:
                        CustomFilterTabView(preferences: preferences)
                    case let tab:
                        // A fresh list per tab: reusing one List for every tab left the old
                    // rows and scroll offset behind and made the switch look broken.
                    HomeTabListView(tab: tab).id(tab)
                    }
                }
                // Only the tab indicator/strip moves. New lists and their loading
                // state must not inherit the selection's animation transaction.
                .transaction {
                    if selectionMotion.shouldAnimate(selection ?? preferences.defaultTab) {
                        $0.animation = nil; $0.disablesAnimations = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingSearch) {
                HomeSearchView()
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingDefaultTab) {
                HomeDefaultTabSheet(preferences: preferences)
            }
            .task(id: env.session.viewerKey) {
                if selection == nil { selection = preferences.defaultTab }
                await env.session.refreshNotificationCount()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        BrowsingHeader(onSettings: { isShowingSettings = true })
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        HStack(spacing: 0) {
            // The Android strip pins the filter button to the left of the scrolling
            // tabs rather than scrolling it away with them.
            Menu {
                Button("Изменить вкладку по умолч.") { isShowingDefaultTab = true }
                Button("Настроить мою вкладку") {
                    // Opening this route selects the custom tab, but does not
                    // change the device's separately saved launch default.
                    selection = .custom
                    isShowingTabSettings = true
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .zIndex(1)
            .accessibilityLabel("Настройки вкладок")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(HomeTab.allCases) { tab in
                            tabButton(tab)
                                .id(tab)
                        }
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
                }
                .clipped()
                .onAppear {
                    reveal(selection ?? preferences.defaultTab, with: proxy)
                }
                .onChange(of: selection) { _, new in
                    guard let new, new == selection else { return }
                    motion.perform(animated: selectionMotion.shouldAnimate(new)) { reveal(new, with: proxy) }
                    selectionMotion.complete(new)
                }
            }
        }
        .sheet(isPresented: $isShowingTabSettings) {
            CustomTabSettingsView(
                current: preferences.customFilter ?? CustomTabFilter(),
                onApply: {
                    preferences.save(customFilter: $0)
                    selection = .custom
                },
                onReset: { preferences.save(customFilter: nil) }
            )
        }
    }

    /// Brings the selected tab into view. The first few tabs sit within the first screen of
    /// the strip, so it stays at the start and «Моя вкладка» is always fully visible next
    /// to the settings button; only tabs further along are scrolled in.
    private func reveal(_ tab: HomeTab, with proxy: ScrollViewProxy) {
        let index = HomeTab.allCases.firstIndex(of: tab) ?? 0
        if index <= 3 {
            proxy.scrollTo(HomeTab.allCases[0], anchor: .leading)
        } else {
            proxy.scrollTo(tab, anchor: .center)
        }
    }

    private func tabButton(_ tab: HomeTab) -> some View {
        let isSelected = (selection ?? preferences.defaultTab) == tab
        let title = tab == .custom ? preferences.customTabTitle : tab.title

        return Button { select(tab) } label: {
            // The beta marks the active tab with a tonal pill instead of an underline.
            SelectionLabel(title: title, isSelected: isSelected)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    SelectionChipBackground(isSelected: isSelected, shape: Capsule(),
                                            color: Theme.accent.opacity(0.3), namespace: tabIndicator)
                }
                .fixedSize()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onKeyPress(.return) { select(tab, fromKeyboard: true); return .handled }
        .onKeyPress(.space) { select(tab, fromKeyboard: true); return .handled }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button {
                preferences.setDefaultTab(tab)
            } label: {
                Label("Сделать вкладкой по умолчанию", systemImage: "pin")
            }
            .disabled(preferences.defaultTab == tab)
        }
    }

    private func select(_ tab: HomeTab, fromKeyboard: Bool = false) {
        guard (selection ?? preferences.defaultTab) != tab else { return }
        selectionMotion.register(tab, fromKeyboard: fromKeyboard)
        motion.perform(animated: !fromKeyboard) { selection = tab }
    }
}

/// Release search, reached from the Главная search field.
@MainActor
struct HomeSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CatalogViewModel?
    @State private var isShowingFilter = false
    @State private var history: ReleaseSearchHistoryStore?

    var body: some View {
        Group {
            if let model, model.hasCurrentViewer {
                if model.hasAppliedFilter, !model.isShowingSearch {
                    FilteredReleasesView(filter: model.filter, title: "Результаты фильтра", viewer: model.viewer, paginator: model.browse)
                        .id(ObjectIdentifier(model.browse))
                } else { ReleaseSearchResultsView(model: model) }
            }
            else { ProgressView() }
        }
        .navigationTitle(model?.hasAppliedFilter == true && model?.isShowingSearch == false ? "Результаты фильтра" : "Поиск")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let model { ReleaseSearchScopeMenu(model: model) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let model { ReleaseSearchInputButton(model: model) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingFilter = true } label: {
                    Image(systemName: (model?.activeFilterCount ?? 0) > 0
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Полный фильтр")
                .disabled(model?.hasCurrentViewer != true)
            }
        }
        .sheet(isPresented: $isShowingFilter) {
            if let model {
                FilterSheet(current: model.filter, onApply: { model.apply(filter: $0) }, onReset: { model.resetFilter() })
            }
        }
        .sheet(isPresented: voiceSearchPresentationBinding(model)) {
            if let input = model?.voiceInput {
                VoiceSearchSheet(model: input, onCancel: { model?.closeVoiceSearch(ifCurrent: input) },
                                 onRetry: { model?.retryVoiceSearch(ifCurrent: input) })
            }
        }
        .searchable(
            text: Binding(get: { model?.query ?? "" }, set: { model?.query = $0 }),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Поиск аниме"
        )
        .onSubmit(of: .search) { model?.rememberSearch() }
        .task(id: env.session.viewerKey) {
            // Token replacement/reauthentication temporarily hides accountKey
            // while retaining the signed-in profile. Do not turn its draft into
            // guest history or erase it before the settled viewer is known.
            if env.session.isSignedIn, env.session.viewerKey.account == nil {
                model?.setVoiceSearchActive(false)
                isShowingFilter = false
                return
            }
            if model?.viewer != env.session.viewerKey {
                model?.setVoiceSearchActive(false)
                let keepsQuery = model?.viewer.account?.profileID == env.session.viewerKey.account?.profileID
                let retainedQuery = keepsQuery ? (model?.query ?? "") : ""
                history = ReleaseSearchHistoryStore(profileID: env.session.viewerKey.account?.profileID)
                model = CatalogViewModel(session: env.session, filter: model?.filter ?? FilterRequest(),
                                          query: retainedQuery, searchScope: model?.searchScope ?? .all,
                                         hasAppliedFilter: model?.hasAppliedFilter ?? false, history: history)
                isShowingFilter = false
            }
            model?.setVoiceSearchActive(scenePhase == .active)
        }
        .onAppear { model?.setVoiceSearchActive(scenePhase == .active) }
        .onDisappear { model?.setVoiceSearchActive(false) }
        .onChange(of: scenePhase) { _, phase in model?.setVoiceSearchActive(phase == .active) }
        .task(id: model?.searchKey) {
            await model?.search()
        }
    }
}
