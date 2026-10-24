import Foundation
import AnixartKit

/// Home screen. Each block is a separate endpoint, so they load concurrently and
/// a block that fails is simply omitted rather than taking the screen down.
@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var banners: [Interesting] = []
    private(set) var discussing: [Release] = []
    private(set) var continueWatching: [Release] = []
    private(set) var recommendations: [Release] = []
    private(set) var commentsOfTheWeek: [ReleaseComment] = []

    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: AnixartClient
    private let session: SessionController

    init(client: AnixartClient, session: SessionController) {
        self.client = client
        self.session = session
    }

    var isEmpty: Bool {
        banners.isEmpty && discussing.isEmpty && continueWatching.isEmpty
            && recommendations.isEmpty && commentsOfTheWeek.isEmpty
    }

    func loadIfNeeded() async {
        guard isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        // `client` is an actor, so capturing it (rather than `self`) keeps these child
        // tasks sendable while the view model stays on the main actor.
        let client = self.client
        let signedIn = session.isSignedIn

        // The blocks load together; each one keeps its own failure to itself.
        async let bannersTask = Self.attempt {
            try await client.send(DiscoverEndpoints.interesting()).items
        }
        async let discussingTask = Self.attempt {
            try await client.send(DiscoverEndpoints.discussing()).items
        }
        async let commentsTask = Self.attempt {
            try await client.send(DiscoverEndpoints.commentsOfTheWeek()).items
        }
        async let watchingTask = Self.attempt { () -> [Release] in
            guard signedIn else { return [] }
            return try await client.send(DiscoverEndpoints.watching(page: 0)).items
        }
        async let recommendationsTask = Self.attempt { () -> [Release] in
            guard signedIn else { return [] }
            return try await client.send(DiscoverEndpoints.recommendations(page: 0)).items
        }

        banners = (await bannersTask ?? []).filter { $0.isHidden != true }
        discussing = await discussingTask ?? []
        commentsOfTheWeek = await commentsTask ?? []
        continueWatching = await watchingTask ?? []
        recommendations = await recommendationsTask ?? []

        isLoading = false
        if isEmpty {
            errorMessage = "Не удалось загрузить главную. Проверьте соединение."
        }
    }

    /// Runs a block and swallows its failure, so one dead block does not blank the screen.
    /// `nonisolated static` so it can run off the main actor inside `async let`.
    private nonisolated static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> T? {
        try? await work()
    }
}
