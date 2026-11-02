import Foundation
import AnixartKit

struct AppLaunchPolicy: Sendable {
    var configurationTimeout: Duration = .seconds(4)
    var sessionTimeout: Duration = .seconds(4)
    var firstPageTimeout: Duration = .seconds(12)
}

/// Home's device-local starting tab, not the last root tab or a server preference.
/// A configured-but-unconstrained custom tab is valid; an unset one has no feed.
struct AppLaunchHomeTarget: Equatable {
    let tab: HomeTab
    let filter: FilterRequest

    @MainActor
    static func resolve(screen: LaunchScreen, preferences: HomePreferences) -> Self? {
        // Release/player/Kodik routes also report a Home root tab. Only the actual
        // Home launch should warm it; diagnostic routes keep their existing work.
        guard screen == .home else { return nil }
        let tab = preferences.defaultTab
        let filter = tab == .custom ? preferences.customFilter?.filterRequest : tab.filter
        guard let filter else { return nil }
        return Self(tab: tab, filter: filter)
    }
}

/// One cold start per environment. The app owns this object, not a view task or
/// scenePhase, so reappearing/foregrounding cannot replay launch or rebuild tabs.
@MainActor
@Observable
final class AppLaunchCoordinator {
    enum Phase: Equatable {
        case notStarted, loadingConfiguration, restoringSession, loadingHome, ready
    }

    private(set) var phase: Phase = .notStarted
    var isReady: Bool { phase == .ready }

    private let session: SessionController
    private let screen: LaunchScreen
    private let defaults: UserDefaults
    private let policy: AppLaunchPolicy
    private let deadline: AppLaunchDeadline
    private let loadConfiguration: @MainActor @Sendable () async throws -> Void
    private let restoreSession: @MainActor @Sendable () async throws -> Void
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    private var warmHomeFeed: WarmHomeFeed?

    init(
        session: SessionController,
        screen: LaunchScreen = .current,
        defaults: UserDefaults = .standard,
        policy: AppLaunchPolicy = AppLaunchPolicy(),
        deadline: AppLaunchDeadline = AppLaunchDeadline(),
        loadConfiguration: (@MainActor @Sendable () async throws -> Void)? = nil,
        restoreSession: (@MainActor @Sendable () async throws -> Void)? = nil
    ) {
        self.session = session
        self.screen = screen
        self.defaults = defaults
        self.policy = policy
        self.deadline = deadline
        self.loadConfiguration = loadConfiguration ?? { await session.loadRemoteConfiguration() }
        self.restoreSession = restoreSession ?? { await session.restore() }
    }

    func startIfNeeded() async {
        if let startupTask { await startupTask.value; return }
        // Deliberately unstructured: cancellation of SwiftUI's waiter must not
        // cancel cold start and leave the next appearance with an unloaded feed.
        let task = Task { await prepare() }
        startupTask = task
        await task.value
    }

    /// Read-only lookup lets the very first Home render show the warmed state,
    /// before its .task transfers ownership into the tab's @State.
    func prewarmedHomeFeed(for tab: HomeTab, key: ReleaseFeedKey) -> ReleaseFeedModel? {
        guard isReady, let warmHomeFeed,
              warmHomeFeed.target.tab == tab, warmHomeFeed.target.filter == key.filter,
              warmHomeFeed.model.viewer == key.viewer, warmHomeFeed.model.hasCurrentViewer
        else { return nil }
        return warmHomeFeed.model
    }

    /// A single handoff, not a long-lived feed cache. If preferences/viewer changed
    /// before Home mounted, discard rather than using it on some later tab visit.
    func takePrewarmedHomeFeed(for tab: HomeTab, key: ReleaseFeedKey) -> ReleaseFeedModel? {
        defer { warmHomeFeed = nil }
        return prewarmedHomeFeed(for: tab, key: key)
    }

    func discardPrewarmedFeed(ifViewerChangedTo viewer: ProfileViewerKey) {
        if warmHomeFeed?.model.viewer != viewer { warmHomeFeed = nil }
    }

    private func prepare() async {
        defer { phase = .ready }
        // Config can replace the host, so no session/feed request runs before this
        // stage settles (success, failure or deadline). Both stages are best-effort.
        phase = .loadingConfiguration
        let configure = loadConfiguration
        _ = try? await deadline.run(for: policy.configurationTimeout) { try await configure() }

        phase = .restoringSession
        let restore = restoreSession
        _ = try? await deadline.run(for: policy.sessionTimeout) { try await restore() }
        // A very slow credential store can time out before restore publishes even
        // a guest state. Retire that loading state without clearing credentials;
        // its cancelled late callback must not change the viewer under Home.
        session.finishLaunchRestorationIfNeeded()

        // Re-read local settings now, rather than retaining a preference object
        // that could disagree with the one Home creates when it first mounts.
        guard let target = AppLaunchHomeTarget.resolve(screen: screen, preferences: HomePreferences(defaults: defaults))
        else { return }
        phase = .loadingHome
        let model = makeWarmFeed(for: target)
        await model.paginator.loadFirstPageIfNeeded()
        // Keep failures too: PaginatedContent will show its ordinary retry instead
        // of launching a second first-page request as soon as the splash goes away.
        if model.hasCurrentViewer { warmHomeFeed = WarmHomeFeed(target: target, model: model) }
    }

    private func makeWarmFeed(for target: AppLaunchHomeTarget) -> ReleaseFeedModel {
        let viewer = session.viewerKey
        let request = viewer.account == nil ? target.filter.withoutProfileListExclusions : target.filter
        let loader = AppLaunchFirstPageLoader(
            session: session, viewer: viewer, request: request,
            deadline: deadline, timeout: policy.firstPageTimeout
        )
        let paginator = Paginator<Release>(rawPageSize: 25) { page in try await loader.fetch(page) }
        // The constructor takes the same viewer without any intervening await.
        return ReleaseFeedModel(filter: target.filter, session: session, paginator: paginator)
    }

    private struct WarmHomeFeed {
        let target: AppLaunchHomeTarget
        let model: ReleaseFeedModel
    }
}

/// Only the initial warm attempt gets the launch deadline. User retries, refresh
/// and later pages retain normal client timeouts and the same immutable viewer.
private actor AppLaunchFirstPageLoader {
    private let session: SessionController
    private let viewer: ProfileViewerKey
    private let request: FilterRequest
    private let deadline: AppLaunchDeadline
    private let timeout: Duration
    private var isLaunchAttempt = true

    init(session: SessionController, viewer: ProfileViewerKey, request: FilterRequest,
         deadline: AppLaunchDeadline, timeout: Duration) {
        self.session = session
        self.viewer = viewer
        self.request = request
        self.deadline = deadline
        self.timeout = timeout
    }

    func fetch(_ page: Int) async throws -> PageableResponse<Release> {
        guard page == 0, isLaunchAttempt else {
            return try await session.sendViewerRequest(CatalogEndpoints.filter(request, page: page), for: viewer)
        }
        isLaunchAttempt = false
        let session = self.session
        let viewer = self.viewer
        let request = self.request
        do {
            return try await deadline.run(for: timeout) {
                try await session.sendViewerRequest(CatalogEndpoints.filter(request, page: page), for: viewer)
            }
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw AnixartError.transport(message: "Время ожидания истекло. Повторите попытку.", isOffline: false)
            }
            if ProfileRequestFailure.isCancellation(error), !Task.isCancelled {
                let currentViewer = await session.viewerKey
                if currentViewer == viewer, !Task.isCancelled {
                    // A still-current viewer's cancelled initial transport must not
                    // silently become an idle/unloaded paginator and another spinner.
                    throw AnixartError.transport(message: "Загрузка прервана. Повторите попытку.", isOffline: false)
                }
            }
            throw error
        }
    }
}
