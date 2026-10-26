import SwiftUI
import AnixartKit

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: Tab = LaunchScreen.current.tab

    enum Tab: Hashable {
        case home, discover, catalog, bookmarks, profile
    }

    var body: some View {
        Group {
            switch LaunchScreen.current {
            case .release(let id):
                NavigationStack { ReleaseDetailView(releaseID: id) }
            case .randomRelease:
                NavigationStack { RandomReleaseScreen() }
            case .player(let id):
                PlayerSmokeScreen(releaseID: id)
            case .profile where env.session.currentProfileID == nil:
                NavigationStack { SampleProfileScreen() }
            default:
                tabs
            }
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

    private var tabs: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Главная", systemImage: "house") }
                .tag(Tab.home)

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
    }
}

/// Which screen to open on launch.
///
/// Normally `.home`. CI passes `-anixart-screen <name>` so the smoke test can
/// photograph a screen other than the one the app starts on -- there is no UI
/// automation in the workflow, and a screenshot is the only check that a screen
/// actually renders against live data.
enum LaunchScreen: Equatable {
    case home
    case profile
    case catalog
    case release(Int)
    /// `release` with no id: the smoke test does not know a live release id, so
    /// the app asks the server for one.
    case randomRelease
    /// Resolves an episode and opens the built-in player on it, so the smoke
    /// test checks playback rather than only that the code compiles.
    case player(Int)

    static let current: LaunchScreen = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-anixart-screen"),
              arguments.indices.contains(index + 1)
        else { return .home }

        let value = arguments[index + 1]
        switch value {
        case "profile": return .profile
        case "catalog": return .catalog
        case "release": return .randomRelease
        // «Киберпанк: Бегущие по краю», the release the CI probe showed lists an
        // AniLibria hosting.
        case "player": return .player(18846)
        default:
            if value.hasPrefix("release:"), let id = Int(value.dropFirst("release:".count)) {
                return .release(id)
            }
            if value.hasPrefix("player:"), let id = Int(value.dropFirst("player:".count)) {
                return .player(id)
            }
            return .home
        }
    }()

    var tab: RootView.Tab {
        switch self {
        case .profile: return .profile
        case .catalog: return .catalog
        default: return .home
        }
    }
}

/// Opens whatever release `release/random` hands back. Only reachable through
/// the `-anixart-screen release` launch argument the smoke test uses.
@MainActor
struct RandomReleaseScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var release: Release?

    var body: some View {
        Group {
            if let release {
                ReleaseDetailView(releaseID: release.id, preloaded: release)
            } else {
                ProgressView()
            }
        }
        .task {
            guard release == nil else { return }
            let response = try? await env.client.send(ReleaseEndpoints.random(extended: true))
            release = response?.release
        }
    }
}

/// Someone's public profile, for the smoke test only: CI has no credentials, so
/// the Профиль tab would photograph the sign-in prompt rather than the screen
/// this is meant to check. Reached only through `-anixart-screen profile`.
@MainActor
struct SampleProfileScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var profileID: Int?

    var body: some View {
        Group {
            if let profileID {
                ProfileView(profileID: profileID)
            } else {
                ProgressView()
            }
        }
        .task {
            guard profileID == nil else { return }
            let page = try? await env.client.send(CatalogEndpoints.searchProfiles("a", page: 0))
            profileID = page?.content?.first?.id
        }
    }
}
