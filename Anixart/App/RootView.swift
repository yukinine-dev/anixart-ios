import SwiftUI
import AnixartKit

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: Tab = .discover

    enum Tab: Hashable {
        case discover, catalog, bookmarks, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            DiscoverView()
                .tabItem { Label("Обзор", systemImage: "square.grid.2x2") }
                .tag(Tab.discover)

            CatalogView()
                .tabItem { Label("Каталог", systemImage: "magnifyingglass") }
                .tag(Tab.catalog)

            BookmarksView()
                .tabItem { Label("Закладки", systemImage: "bookmark") }
                .tag(Tab.bookmarks)

            ProfileTabView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
                .badge(env.session.unreadNotifications)
        }
        .tint(Theme.accent)
        // Most of Anixart works signed out, so any screen that needs a session asks
        // for the sheet through the session object rather than owning it.
        .sheet(isPresented: Binding(
            get: { env.session.isPresentingAuth },
            set: { env.session.isPresentingAuth = $0 }
        )) {
            AuthView()
        }
    }
}
