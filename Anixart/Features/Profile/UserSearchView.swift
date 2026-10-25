import SwiftUI
import AnixartKit

/// "Поиск пользователей" from the profile header.
@MainActor
struct UserSearchView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var query = ""
    @State private var paginator: Paginator<Profile>?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Никого не нашлось") { profile in
                    NavigationLink {
                        ProfileView(profileID: profile.id)
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
            } else {
                Text("Введите никнейм")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Поиск пользователей")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Никнейм")
        // Debounced so typing does not fire a request per keystroke.
        .onChange(of: query) { _, new in
            searchTask?.cancel()
            let trimmed = new.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                paginator = nil
                return
            }
            let client = env.client
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let fresh = Paginator<Profile> { page in
                    try await client.send(CatalogEndpoints.searchProfiles(trimmed, page: page))
                }
                paginator = fresh
                await fresh.loadFirstPageIfNeeded()
            }
        }
    }
}
