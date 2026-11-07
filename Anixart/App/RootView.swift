import SwiftUI
import AnixartKit

@MainActor
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: Tab = LaunchScreen.current.tab
    @State private var homeNavigationRevision = 0

    enum Tab: Hashable, CaseIterable {
        // Four root sections plus search (the beta moved Профиль behind the avatar); catalogue browsing
        // belongs to Home/search/filter routes, never to an additional root tab.
        case home, discover, bookmarks, feed, search

        var title: String {
            switch self {
            case .home: return "Главная"
            case .discover: return "Обзор"
            case .bookmarks: return "Закладки"
            case .feed: return "Лента"
            case .search: return "Поиск"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .discover: return "safari"
            case .bookmarks: return "bookmark"
            case .feed: return "rectangle.topthird.inset.filled"
            case .search: return "magnifyingglass"
            }
        }
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
            case .kodik(let id):
                KodikProbeScreen(releaseID: id)
            case .profile where env.session.currentProfileID == nil:
                NavigationStack { SampleProfileScreen() }
            case .profile:
                NavigationStack { ProfileTabView() }
            default:
                tabs
            }
        }
        .environment(\.returnToHome, homeAction)
        .anixartAppearance()
        .anixartColorScheme()
        // Most of Anixart works signed out, so any screen that needs a session asks
        // for the sheet through the session object rather than owning it.
        .sheet(isPresented: Binding(
            get: { env.session.isPresentingAuth },
            set: { env.session.isPresentingAuth = $0 }
        )) {
            AuthView()
        }
    }

    /// The new Android bottom bar: four sections and a separate round search button.
    /// iOS 18 and later draw the `.search` role as that detached button (and as part
    /// of the floating glass bar on iOS 26); earlier systems get a plain fifth tab.
    @ViewBuilder
    private var tabs: some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                SwiftUI.Tab(Tab.home.title, systemImage: Tab.home.systemImage, value: Tab.home) { tabContent(.home) }
                SwiftUI.Tab(Tab.discover.title, systemImage: Tab.discover.systemImage, value: Tab.discover) { tabContent(.discover) }
                SwiftUI.Tab(Tab.bookmarks.title, systemImage: Tab.bookmarks.systemImage, value: Tab.bookmarks) { tabContent(.bookmarks) }
                SwiftUI.Tab(Tab.feed.title, systemImage: Tab.feed.systemImage, value: Tab.feed) { tabContent(.feed) }
                SwiftUI.Tab(Tab.search.title, systemImage: Tab.search.systemImage, value: Tab.search, role: .search) { tabContent(.search) }
            }
        } else {
            legacyTabs
        }
        #else
        legacyTabs
        #endif
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabContent(tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
    }

    private var homeAction: RootHomeAction? {
        switch LaunchScreen.current {
        case .release, .randomRelease, .player, .kodik: return nil
        case .profile where env.session.currentProfileID == nil: return nil
        default:
            return RootHomeAction {
                homeNavigationRevision += 1
                selection = .home
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: Tab) -> some View {
        switch tab {
        case .home: HomeView().id(homeNavigationRevision)
        case .discover: DiscoverView()
        case .bookmarks: BookmarksView()
        case .feed: FeedView()
        case .search: NavigationStack { HomeSearchView() }
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
    case feed
    case release(Int)
    /// `release` with no id: the smoke test does not know a live release id, so
    /// the app asks the server for one.
    case randomRelease
    /// Resolves an episode and opens the built-in player on it, so the smoke
    /// test checks playback rather than only that the code compiles.
    case player(Int)
    /// Loads a Kodik episode through the advert screen and logs what the page
    /// played. The stream is not in that page's HTML, so this is the only way to
    /// measure it.
    case kodik(Int)

    static let current: LaunchScreen = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-anixart-screen"),
              arguments.indices.contains(index + 1)
        else { return .home }

        let value = arguments[index + 1]
        switch value {
        case "profile": return .profile
        case "feed": return .feed
        // Retire the old diagnostic route without resurrecting a nonexistent tab.
        case "catalog": return .home
        case "release": return .randomRelease
        // «Киберпанк: Бегущие по краю», the release the CI probe showed lists an
        // AniLibria hosting.
        case "player": return .player(18846)
        case "kodik": return .kodik(18846)
        default:
            if value.hasPrefix("release:"), let id = Int(value.dropFirst("release:".count)) {
                return .release(id)
            }
            if value.hasPrefix("player:"), let id = Int(value.dropFirst("player:".count)) {
                return .player(id)
            }
            if value.hasPrefix("kodik:"), let id = Int(value.dropFirst("kodik:".count)) {
                return .kodik(id)
            }
            return .home
        }
    }()

    var tab: RootView.Tab {
        switch self {
        case .profile: return .home
        case .feed: return .feed
        default: return .home
        }
    }
}

/// Opens a random release's detail, never a player. Used by Обзор and CI's
/// `-anixart-screen release` smoke route; a failure has an explicit retry.
@MainActor
struct RandomReleaseScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model: RandomReleaseViewModel?

    var body: some View {
        Group {
            if let model, !model.hasCurrentViewer {
                ProfileViewerNotice(viewer: model.viewer)
            } else if let model, let release = model.release {
                ReleaseDetailView(releaseID: release.id, preloaded: release, viewer: model.viewer).id(release.id)
            } else if let model, let error = model.errorMessage {
                StatusMessageView(title: "Не удалось выбрать релиз", message: error,
                                  systemImage: "wifi.exclamationmark", retry: { await model.load() })
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil { model = RandomReleaseViewModel(session: env.session) }
            if model?.release == nil { await model?.load() }
        }
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: env.session.viewerKey) { _, current in if model?.viewer != current { model?.invalidate() } }
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
