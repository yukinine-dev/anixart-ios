import SwiftUI
import AnixartKit

/// "Моя вкладка": the user's own filter over the catalogue.
///
/// Until it is configured there is nothing sensible to fetch, so the tab shows the
/// same prompt the Android app does rather than an arbitrary unfiltered list.
@MainActor
struct CustomFilterTabView: View {
    @Environment(AppEnvironment.self) private var env

    let preferences: HomePreferences

    @State private var model: ReleaseFeedModel?
    @State private var isShowingSettings = false
    @State private var opened: Release?
    @State private var listTarget: Release?

    private var currentModel: ReleaseFeedModel? {
        guard let filter = preferences.customFilter?.filterRequest else { return nil }
        let key = ReleaseFeedKey(filter: filter, viewer: env.session.viewerKey)
        if let model, model.hasCurrentViewer, model.viewer == key.viewer, model.filter == key.filter {
            return model
        }
        return env.launch.prewarmedHomeFeed(for: .custom, key: key)
    }

    var body: some View {
        Group {
            if let filter = preferences.customFilter {
                list(for: filter)
            } else {
                emptyState
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            CustomTabSettingsView(
                current: preferences.customFilter ?? CustomTabFilter(),
                onApply: { preferences.save(customFilter: $0) },
                onReset: { preferences.save(customFilter: nil) }
            )
        }
        .sheet(item: $listTarget) { release in
            if let model = currentModel { ReleaseQuickActionsSheet(release: release, viewer: model.viewer, feed: model) }
        }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: currentModel?.viewer)
        }
        .onChange(of: preferences.customFilter) { _, new in
            if new == nil { model = nil }
            listTarget = nil
            opened = nil
        }
        .onChange(of: env.session.viewerKey) { _, _ in listTarget = nil; opened = nil }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Это ваша вкладка")
                .font(.ax(.headline))
            Text("Настройте её под себя и укажите,\nчто хотели бы здесь видеть")
                .font(.ax(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Настроить") { isShowingSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func list(for filter: CustomTabFilter) -> some View {
        List {
            if let model = currentModel, model.filter == filter.filterRequest {
                PaginatedContent(
                    paginator: model.paginator,
                    emptyTitle: "Ничего не найдено",
                    emptyMessage: "К сожалению, не удалось ничего найти по заданным фильтрам"
                ) { release in
                    ReleaseListRow(release: release) { listTarget = release }
                        .onTapGesture { opened = release }
                        // The row draws its own card, so the list must not draw a
                        // background or a separator behind it.
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await currentModel?.paginator.reload() }
        .safeAreaInset(edge: .top) {
            Button {
                isShowingSettings = true
            } label: {
                Label(
                    filter.activeCount > 0 ? "Фильтры: \(filter.activeCount)" : "Настроить вкладку",
                    systemImage: "slider.horizontal.3"
                )
                .font(.ax(.subheadline))
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        // Reloads whenever the stored filter changes.
        .task(id: ReleaseFeedKey(filter: filter.filterRequest, viewer: env.session.viewerKey)) {
            let key = ReleaseFeedKey(filter: filter.filterRequest, viewer: env.session.viewerKey)
            if model?.viewer != key.viewer || model?.filter != key.filter {
                model = env.launch.takePrewarmedHomeFeed(for: .custom, key: key)
                    ?? ReleaseFeedModel(filter: key.filter, session: env.session)
            }
            let current = model
            await current?.paginator.loadFirstPageIfNeeded()
        }
    }
}
