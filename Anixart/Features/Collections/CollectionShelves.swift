import SwiftUI
import AnixartKit

/// The three shelves the beta 3 «Коллекции» screen opens with.
///
/// «Под ваш вкус» is worked out on the device from public collections: a collection
/// qualifies when at least two of its releases are among the viewer's recent
/// «Смотрю» / «Просмотрено» titles. Collections they bookmarked, made themselves or
/// have fully watched are left out, and the card shows «Совпадение» -- the share of
/// the collection's releases already in those lists.
@MainActor
@Observable
final class CollectionShelvesModel {
    struct Match: Identifiable, Hashable {
        let collection: ReleaseCollection
        let shared: Int
        let percent: Int
        var id: Int { collection.id }
    }

    private(set) var weekly: [ReleaseCollection] = []
    private(set) var mine: [ReleaseCollection] = []
    private(set) var taste: [Match] = []
    private var loadedFor: ProfileViewerKey?

    func load(viewer: ProfileViewerKey, session: SessionController) async {
        guard loadedFor != viewer else { return }
        let weeklyPages = await Self.pages(count: 2) { page in
            try await session.sendViewerRequest(CollectionEndpoints.ofTheWeek(page: page), for: viewer).items
        }
        guard !Task.isCancelled, viewer == session.viewerKey else { return }
        weekly = Self.unique(weeklyPages)
        guard let account = viewer.account else {
            mine = []
            taste = []
            loadedFor = viewer
            return
        }

        let own = (try? await session.sendAccountRequest(CollectionEndpoints.byProfile(account.profileID, page: 0), for: account).items) ?? []
        mine = own

        var libraryIDs = Set<Int>()
        var completedIDs = Set<Int>()
        for status in [ProfileListStatus.watching, .completed] {
            let page = (try? await session.sendAccountRequest(BookmarkEndpoints.list(status, page: 0), for: account).items) ?? []
            for release in page {
                libraryIDs.insert(release.id)
                if status == .completed { completedIDs.insert(release.id) }
            }
        }
        guard !Task.isCancelled, viewer == session.viewerKey else { return }

        let browsed = await Self.pages(count: 3) { page in
            try await session.sendViewerRequest(CollectionEndpoints.all(page: page, previousPage: max(0, page - 1)), for: viewer).items
        }
        guard !Task.isCancelled, viewer == session.viewerKey else { return }
        let candidates = Self.unique(weekly + browsed)
        taste = Self.rank(candidates, library: libraryIDs, completed: completedIDs, profileID: account.profileID)
        loadedFor = viewer
    }

    static func rank(_ collections: [ReleaseCollection], library: Set<Int>, completed: Set<Int>, profileID: Int) -> [Match] {
        collections.compactMap { collection -> Match? in
            guard collection.isFavorite != true, collection.creator?.id != profileID,
                  let releases = collection.releases, !releases.isEmpty else { return nil }
            let ids = releases.map(\.id)
            let shared = ids.filter(library.contains).count
            guard shared >= 2 else { return nil }
            guard !ids.allSatisfy(completed.contains) else { return nil }
            return Match(collection: collection, shared: shared, percent: shared * 100 / ids.count)
        }
        .sorted { $0.shared != $1.shared ? $0.shared > $1.shared : $0.percent > $1.percent }
    }

    private static func pages(count: Int, _ fetch: (Int) async throws -> [ReleaseCollection]) async -> [ReleaseCollection] {
        var result: [ReleaseCollection] = []
        for page in 0..<count {
            guard let items = try? await fetch(page), !items.isEmpty else { break }
            result += items
        }
        return result
    }

    private static func unique(_ collections: [ReleaseCollection]) -> [ReleaseCollection] {
        var seen = Set<Int>()
        return collections.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
struct CollectionShelves: View {
    @Environment(AppEnvironment.self) private var env
    let viewer: ProfileViewerKey
    @State private var model = CollectionShelvesModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.row) {
            shelf("Популярные за неделю", collections: model.weekly)
            shelf("Созданные вами", collections: model.mine)
            if !model.taste.isEmpty {
                Text("Под ваш вкус").font(.ax(.title3, .semibold)).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.row) {
                        ForEach(model.taste) { match in
                            NavigationLink {
                                CollectionByIDView(collectionID: match.collection.id, viewer: viewer)
                            } label: {
                                OverviewCollectionCard(collection: match.collection)
                                    .overlay(alignment: .bottomTrailing) {
                                        Text("Совпадение \(match.percent)%")
                                            .font(.ax(.caption, .semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(.black.opacity(0.65), in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(12)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 8)
        .task(id: viewer.revision) {
            guard viewer == env.session.viewerKey else { return }
            await model.load(viewer: viewer, session: env.session)
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, collections: [ReleaseCollection]) -> some View {
        if !collections.isEmpty {
            Text(title).font(.ax(.title3, .semibold)).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Spacing.row) {
                    ForEach(collections) { collection in
                        NavigationLink {
                            CollectionByIDView(collectionID: collection.id, viewer: viewer)
                        } label: { OverviewCollectionCard(collection: collection) }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
