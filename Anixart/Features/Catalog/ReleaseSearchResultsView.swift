import SwiftUI
import AnixartKit

/// Shared by the catalogue and the Главная search entry. Both routes support the
/// same franchise suggestion, pagination, retry and viewer-scoped navigation.
@MainActor
struct ReleaseSearchResultsView: View {
    let model: CatalogViewModel
    @State private var opened: Release?
    @State private var actionTarget: Release?

    var body: some View {
        List {
            if !model.isShowingSearch {
                StatusMessageView(title: "Введите название аниме", systemImage: "magnifyingglass")
            } else if let results = model.currentSearch {
                if let related = results.related {
                    Section("Результаты поиска") {
                        NavigationLink {
                            RelatedReleasesView(related: related, viewer: results.viewer)
                        } label: {
                            RelatedSearchResultCard(related: related)
                        }
                    }
                }

                Section(results.related == nil ? "Результаты поиска" : "Другие результаты") {
                    ForEach(results.items) { release in
                        ReleaseListRow(release: release) { actionTarget = release }
                        .onTapGesture { opened = release }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            if release.id == results.items.last?.id {
                                Task { await results.loadNextPage() }
                            }
                        }
                    }
                    if results.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical)
                    } else if let error = results.errorMessage {
                        StatusMessageView(
                            title: results.failedPage == 0 ? "Поиск не удался" : "Не удалось загрузить следующую страницу",
                            message: error, systemImage: "wifi.exclamationmark", retry: { await results.retry() }
                        )
                    } else if results.items.isEmpty, results.related == nil {
                        StatusMessageView(title: "Ничего не найдено", message: "Проверьте написание названия", systemImage: "magnifyingglass")
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.currentSearch?.reload() }
        .navigationDestination(item: $opened) { release in
            ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model.viewer)
        }
        .sheet(item: $actionTarget) { release in
            ReleaseQuickActionsSheet(release: release, viewer: model.viewer)
        }
        .onChange(of: model.searchKey) { _, _ in actionTarget = nil; opened = nil }
    }
}

@MainActor
struct RelatedSearchResultCard: View {
    let related: Related

    var body: some View {
        HStack(spacing: 16) {
            if !related.posterURLs.isEmpty {
                HStack(spacing: -22) {
                    ForEach(Array(related.posterURLs.prefix(3).enumerated()), id: \.offset) { index, url in
                        ReleasePoster(url: url, width: 58).zIndex(Double(3 - index))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(related.displayName).font(.ax(.headline)).foregroundStyle(.primary)
                if let count = related.releaseCountText {
                    Text(count).font(.ax(.subheadline)).foregroundStyle(.secondary)
                }
                Label("Перейти", systemImage: "arrow.right").font(.ax(.subheadline, .medium))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

@MainActor
struct ReleaseSearchScopeMenu: View {
    @Bindable var model: CatalogViewModel

    var body: some View {
        Menu {
            Picker("Искать", selection: $model.searchScope) {
                ForEach(SearchScope.allCases, id: \.rawValue) { scope in
                    Text(scope.title).tag(scope)
                }
            }
        } label: {
            Image(systemName: "text.magnifyingglass")
        }
        .accessibilityLabel("Поиск по названиям")
    }
}
