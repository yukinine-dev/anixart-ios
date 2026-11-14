import SwiftUI
import AnixartKit

/// Shared by the catalogue and the Главная search entry. Both routes support the
/// same franchise suggestion, pagination, retry and viewer-scoped navigation.
@MainActor
struct ReleaseSearchResultsView: View {
    let model: CatalogViewModel
    /// The franchise card above the results; a credit link (director, author, studio)
    /// shows only the plain results, as Android does.
    var showsFranchise = true
    @State private var opened: Release?
    @State private var actionTarget: Release?
    @State private var openedFranchise: Related?

    var body: some View {
        List {
            if !model.isShowingSearch {
                if let history = model.history, !history.entries.isEmpty { ReleaseSearchHistoryView(model: model, history: history) }
                else { StatusMessageView(title: "Введите название аниме", systemImage: "magnifyingglass") }
            } else if let results = model.currentSearch {
                if showsFranchise, let related = results.related {
                    Section {
                        RelatedSearchResultCard(related: related) { model.rememberSearch(); openedFranchise = related }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Результаты поиска").font(.ax(.subheadline)).textCase(nil)
                    }
                }

                Section {
                    ForEach(results.items) { release in
                        ReleaseListRow(release: release, style: .plain) { actionTarget = release }
                        .onTapGesture { model.rememberSearch(); opened = release }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 12))
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
                    } else if results.items.isEmpty, results.related == nil || !showsFranchise {
                        StatusMessageView(title: "Ничего не найдено", message: "Проверьте написание названия", systemImage: "magnifyingglass")
                    }
                } header: {
                    Text(results.related == nil || !showsFranchise ? "Результаты поиска" : "Другие результаты")
                        .font(.ax(.subheadline)).textCase(nil)
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
        .navigationDestination(item: $openedFranchise) { related in
            RelatedReleasesView(related: related, viewer: model.viewer)
        }
        .sheet(item: $actionTarget) { release in
            ReleaseQuickActionsSheet(release: release, viewer: model.viewer)
        }
        .onChange(of: model.searchKey) { _, _ in actionTarget = nil; opened = nil; openedFranchise = nil }
    }
}

@MainActor
struct RelatedSearchResultCard: View {
    @Environment(\.appThemePalette) private var palette
    let related: Related
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            RelatedPosterStack(urls: related.posterURLs)
            Text(related.displayName)
                .font(.ax(.title3, .semibold))
                .foregroundStyle(palette.text.color)
                .multilineTextAlignment(.center)
            if let count = related.releaseCountText {
                Text(count).font(.ax(.subheadline)).foregroundStyle(palette.secondaryText.color)
            }
            // Filled with the theme's own accent, with the theme background as the
            // label colour, so it reads on every theme instead of a fixed black/white.
            Button(action: onOpen) {
                Text("Перейти")
                    .font(.ax(.body, .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(palette.background.color)
                    .background(palette.accent.color, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 220)
            .padding(.top, 6)
            .accessibilityIdentifier("search.franchise.open")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

/// `item_search_related`: a larger centre poster and two smaller, symmetrically
/// offset posters behind it. These are release images, not Related.image (a banner).
@MainActor
struct RelatedPosterStack: View {
    let urls: [URL]

    var body: some View {
        ZStack {
            if urls.count > 1 {
                ReleasePoster(url: urls[1], width: 64, cornerRadius: 16, aspectRatio: 2.0 / 3.0)
                    .offset(x: 60)
            }
            if urls.count > 2 {
                ReleasePoster(url: urls[2], width: 64, cornerRadius: 16, aspectRatio: 2.0 / 3.0)
                    .offset(x: -60)
            }
            ReleasePoster(url: urls.first, width: 86, cornerRadius: 16, aspectRatio: 2.0 / 3.0)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .frame(width: 200, height: 145)
        .accessibilityHidden(true)
    }
}

/// The destination has a separate wide banner, centred title and description
/// (`item_related_header`), rather than the search suggestion's poster stack.
@MainActor
struct RelatedFranchiseHeader: View {
    let related: Related
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 12) {
            if let url = related.bannerURL {
                GeometryReader { geometry in
                    CachedAsyncImage(url: url, maxPixelSize: 1200) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Rectangle().fill(.quaternary) }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }
                .aspectRatio(20.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            }
            Text(related.displayName)
                .font(.ax(.title2, .medium))
                .multilineTextAlignment(.center)
            if let description = related.description, !description.isEmpty {
                ReleaseExpandableText(text: description, alignment: .center, isExpanded: $isExpanded)
            }
            Rectangle().fill(Theme.accent).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

@MainActor
struct ReleaseSearchScopeMenu: View {
    @Bindable var model: CatalogViewModel

    var body: some View {
        Menu {
            Picker("Искать", selection: $model.searchScope) {
                ForEach(SearchScope.titleSearchScopes, id: \.rawValue) { scope in
                    Text(scope.title).tag(scope)
                }
            }
        } label: {
            Image(systemName: "text.magnifyingglass")
        }
        .accessibilityLabel("Область поиска релизов")
    }
}
