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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                tabStrip
                Divider()

                Group {
                    switch selection ?? preferences.defaultTab {
                    case .custom:
                        CustomFilterTabView(preferences: preferences)
                    case let tab:
                        HomeTabListView(tab: tab)
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
        BrowsingHeader(onSearch: { isShowingSearch = true }, onSettings: { isShowingSettings = true })
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Настройки вкладок")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.tabGap) {
                        ForEach(HomeTab.allCases) { tab in
                            tabButton(tab)
                                .id(tab)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.tabGap / 2)
                }
                .onAppear {
                    proxy.scrollTo(selection ?? preferences.defaultTab, anchor: .center)
                }
                .onChange(of: selection) { _, new in
                    guard let new else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
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

    private func tabButton(_ tab: HomeTab) -> some View {
        let isSelected = (selection ?? preferences.defaultTab) == tab
        let title = tab == .custom ? preferences.customTabTitle : tab.title

        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = tab }
        } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.ax(.title3, isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                // The Android strip marks the active tab with a short rounded
                // underline the width of the label.
                Capsule()
                    .fill(isSelected ? Color.primary : .clear)
                    .frame(height: 4)
            }
            .fixedSize()
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                preferences.setDefaultTab(tab)
            } label: {
                Label("Сделать вкладкой по умолчанию", systemImage: "pin")
            }
            .disabled(preferences.defaultTab == tab)
        }
    }

}

/// Release search, reached from the Главная search field.
@MainActor
struct HomeSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CatalogViewModel?
    @State private var isShowingFilter = false

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
        .task(id: env.session.viewerKey) {
            if model?.viewer != env.session.viewerKey {
                model?.setVoiceSearchActive(false)
                model = CatalogViewModel(session: env.session, filter: model?.filter ?? FilterRequest(),
                                         query: model?.query ?? "", searchScope: model?.searchScope ?? .all,
                                         hasAppliedFilter: model?.hasAppliedFilter ?? false)
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
