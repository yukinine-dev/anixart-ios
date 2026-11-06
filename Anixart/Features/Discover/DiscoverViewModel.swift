import Foundation
import AnixartKit

/// Each block is a separate endpoint. Partial failures keep the other blocks (and
/// previously loaded refresh data) usable, without presenting a failure as empty.
@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var banners: [Interesting] = []
    private(set) var discussing: [Release] = []
    private(set) var watchingNow: [Release] = []
    private(set) var recommendations: [Release] = []
    private(set) var commentsOfTheWeek: [ReleaseComment] = []

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var failedBlocks: [String] = []

    private let session: SessionController
    let viewer: ProfileViewerKey
    private var generation = 0
    private var hasAttemptedLoad = false

    init(session: SessionController) {
        self.session = session
        self.viewer = session.viewerKey
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var showsRecommendationExplanation: Bool {
        hasCurrentViewer && hasAttemptedLoad && viewer.account != nil && recommendations.isEmpty
            && !failedBlocks.contains("Рекомендации")
    }
    var partialErrorMessage: String? {
        failedBlocks.isEmpty ? nil : "Не удалось обновить: " + failedBlocks.joined(separator: ", ") + "."
    }

    var isEmpty: Bool {
        banners.isEmpty && discussing.isEmpty && watchingNow.isEmpty
            && recommendations.isEmpty && commentsOfTheWeek.isEmpty
    }

    func loadIfNeeded() async {
        guard !hasAttemptedLoad, !isLoading else { return }
        await load()
    }

    func load() async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        defer { if token == generation { isLoading = false } }

        let session = self.session
        let viewer = self.viewer

        async let bannersTask = Self.attempt {
            try await session.sendViewerRequest(DiscoverEndpoints.interesting(), for: viewer).items
        }
        async let discussingTask = Self.attempt {
            try await session.sendViewerRequest(DiscoverEndpoints.discussing(), for: viewer).items
        }
        async let commentsTask = Self.attempt {
            try await session.sendViewerRequest(DiscoverEndpoints.commentsOfTheWeek(), for: viewer).items
        }
        async let watchingTask = Self.attempt { () -> [Release] in
            guard viewer.account != nil else { return [] }
            return try await session.sendViewerRequest(DiscoverEndpoints.watching(page: 0), for: viewer).items
        }
        async let recommendationsTask = Self.attempt { () -> [Release] in
            guard viewer.account != nil else { return [] }
            return try await session.sendViewerRequest(DiscoverEndpoints.recommendations(page: 0), for: viewer).items
        }

        let (bannerResult, discussingResult, commentResult, watchingResult, recommendationResult) =
            await (bannersTask, discussingTask, commentsTask, watchingTask, recommendationsTask)
        guard token == generation, hasCurrentViewer, !Task.isCancelled else { return }
        // Do not commit a half-cancelled snapshot from a disappearing view.
        guard !bannerResult.wasCancelled, !discussingResult.wasCancelled, !commentResult.wasCancelled,
              !watchingResult.wasCancelled, !recommendationResult.wasCancelled else { return }

        failedBlocks = []
        if let value = bannerResult.value { banners = Self.unique(value.filter { $0.isHidden != true }) }
        else { failedBlocks.append("Интересное") }
        if let value = discussingResult.value { discussing = Self.unique(value) }
        else { failedBlocks.append("Сейчас обсуждают") }
        if let value = commentResult.value { commentsOfTheWeek = Self.unique(value) }
        else { failedBlocks.append("Комментарии недели") }
        if let value = watchingResult.value { watchingNow = Self.unique(value) }
        else { failedBlocks.append("Смотрят сейчас") }
        if let value = recommendationResult.value { recommendations = Self.unique(value) }
        else { failedBlocks.append("Рекомендации") }

        hasAttemptedLoad = true
        if isEmpty, !failedBlocks.isEmpty {
            errorMessage = partialErrorMessage
        }
    }

    private static func unique<Item: Identifiable>(_ items: [Item]) -> [Item] {
        var seen = Set<Item.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> DiscoverBlockResult<T> {
        do { return .loaded(try await work()) }
        catch { return ProfileRequestFailure.isCancellation(error) ? .cancelled : .failed }
    }
}

private enum DiscoverBlockResult<Value: Sendable>: Sendable {
    case loaded(Value), failed, cancelled
    var value: Value? { if case .loaded(let value) = self { return value }; return nil }
    var wasCancelled: Bool { if case .cancelled = self { return true }; return false }
}
