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
    @State private var listTarget: Release?

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
                        HomeTabListView(tab: tab, onOverflow: { listTarget = $0 })
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
            // The row's overflow goes straight to the list picker: on a browsing tab
            // the only thing worth doing to a release you have not opened is filing it.
            .sheet(item: $listTarget) { release in
                ListPickerSheet(current: release.listStatus) { status in
                    Task { await setList(status, for: release) }
                }
            }
            .task {
                if selection == nil { selection = preferences.defaultTab }
                await env.session.refreshNotificationCount()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        GlassGroup(spacing: 12) {
            headerContent
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var headerContent: some View {
        HStack(spacing: 12) {
            Button {
                isShowingSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Поиск аниме")
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassPill()
            }
            .buttonStyle(.plain)

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                NotificationsView()
            } label: {
                Image(systemName: "bell")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .topTrailing) {
                        if env.session.unreadNotifications > 0 {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -2)
                        }
                    }
            }
        }
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        HStack(spacing: 0) {
            // The Android strip pins the filter button to the left of the scrolling
            // tabs rather than scrolling it away with them.
            Button {
                isShowingTabSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.ax(.title3))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

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

    private func setList(_ status: ProfileListStatus?, for release: Release) async {
        guard env.session.isSignedIn else {
            env.session.promptSignIn()
            return
        }
        guard let status else { return }
        _ = try? await env.client.send(
            BookmarkEndpoints.addToList(releaseID: release.id, status: status)
        )
    }
}

/// Release search, reached from the Главная search field.
@MainActor
struct HomeSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: CatalogViewModel?

    var body: some View {
        List {
            if let model {
                if model.isSearching && model.searchResults.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = model.searchError {
                    StatusMessageView(
                        title: "Поиск не удался",
                        message: error,
                        systemImage: "wifi.exclamationmark"
                    )
                } else if model.isShowingSearch && model.searchResults.isEmpty {
                    StatusMessageView(
                        title: "Ничего не найдено",
                        message: "Проверьте написание названия",
                        systemImage: "magnifyingglass"
                    )
                } else {
                    ForEach(model.searchResults) { release in
                        NavigationLink {
                            ReleaseDetailView(releaseID: release.id, preloaded: release)
                        } label: {
                            ReleaseRow(release: release)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Поиск")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: Binding(get: { model?.query ?? "" }, set: { model?.query = $0 }),
            prompt: "Поиск аниме"
        )
        .task {
            if model == nil { model = CatalogViewModel(client: env.client) }
        }
        .task(id: model?.query) {
            await model?.search()
        }
    }
}
