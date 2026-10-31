import SwiftUI
import AnixartKit

/// "Поиск пользователей" from the profile header.
@MainActor
struct UserSearchView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var viewer: ProfileViewerKey?
    @State private var query = ""
    @State private var paginator: Paginator<Profile>?
    @State private var searchTask: Task<Void, Never>?

    init(viewer: ProfileViewerKey? = nil) { _viewer = State(initialValue: viewer) }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Никого не нашлось") { profile in
                    NavigationLink {
                        ProfileView(profileID: profile.id, viewer: viewer)
                    } label: {
                        HStack(spacing: Theme.Spacing.row) {
                            Avatar(url: profile.avatarURL, size: 40, isOnline: profile.isOnline ?? false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayLogin).font(.ax(.headline))
                                if let status = profile.status, !status.isEmpty {
                                    Text(status)
                                        .font(.ax(.caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } else if viewer == env.session.viewerKey {
                Text("Введите никнейм")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Поиск пользователей")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Никнейм")
        .task { if viewer == nil { viewer = env.session.viewerKey } }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            searchTask?.cancel()
            paginator = nil
            query = ""
        }
        .onDisappear { searchTask?.cancel() }
        // Debounced so typing does not fire a request per keystroke.
        .onChange(of: query) { _, new in
            searchTask?.cancel()
            guard let viewer, viewer == env.session.viewerKey else { return }
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                paginator = nil
                return
            }
            let session = env.session
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, session.viewerKey == viewer else { return }
                let fresh = Paginator<Profile> { page in
                    try await session.sendViewerRequest(CatalogEndpoints.searchProfiles(trimmed, page: page), for: viewer)
                }
                paginator = fresh
                await fresh.loadFirstPageIfNeeded()
            }
        }
    }
}
