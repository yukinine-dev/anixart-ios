import Foundation
import AnixartKit

struct ReleaseVideoSection: Identifiable {
    let id: Int
    let category: ReleaseVideoCategory?
    let videos: [ReleaseVideo]
    let rawCount: Int
    var categoryID: Int? { category.flatMap { $0.id > 0 ? $0.id : nil } }
    var showsAll: Bool { categoryID != nil && rawCount >= 25 }
}

/// The full Video hub is different from a category page. The APK renders its
/// blocks and streaming_platforms, then last_videos and later /{page} results.
@MainActor
@Observable
final class ReleaseVideoOverviewModel {
    let releaseID: Int
    let viewer: ProfileViewerKey
    private let session: SessionController
    private(set) var release: Release?
    private(set) var sections: [ReleaseVideoSection] = []
    private(set) var streamingPlatforms: [ReleaseStreamingPlatform] = []
    private(set) var videos: [ReleaseVideo] = []
    private(set) var state: Paginator<ReleaseVideo>.LoadState = .idle
    private(set) var hasMore = false
    private(set) var failedPage: Int?
    private var hasLoaded = false
    private var nextPage = 1
    private var generation = 0
    private var isInvalidated = false

    init(releaseID: Int, viewer: ProfileViewerKey, session: SessionController) {
        self.releaseID = releaseID
        self.viewer = viewer
        self.session = session
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var errorMessage: String? { if case .failed(let message) = state { return message }; return nil }

    func loadIfNeeded() async {
        guard !hasLoaded, state == .idle else { return }
        await reload()
    }

    func reload() async {
        guard !isInvalidated, hasCurrentViewer, !Task.isCancelled else { return }
        generation += 1
        let token = generation
        state = .loading
        failedPage = nil
        do {
            let response = try await session.sendViewerRequest(ReleaseVideoEndpoints.overview(releaseID: releaseID), for: viewer)
            guard response.release?.id == releaseID, let recent = response.lastVideos else {
                throw AnixartError.decoding(message: "Ответ не содержит данные видео этого релиза", path: "video/release/\(releaseID)")
            }
            try Task.checkCancellation()
            guard token == generation, hasCurrentViewer, !isInvalidated else { return }
            release = response.release
            sections = (response.blocks ?? []).enumerated().map { index, block in
                ReleaseVideoSection(id: index, category: block.category, videos: Self.unique(block.videos ?? []),
                                    rawCount: block.videos?.count ?? 0)
            }
            streamingPlatforms = Self.unique(response.streamingPlatforms ?? [])
            videos = Self.unique(recent)
            hasMore = recent.count >= 25
            nextPage = 1
            hasLoaded = true
            state = .idle
        } catch { finishFailure(error, page: 0, generation: token) }
    }

    func loadNextPage() async {
        guard hasLoaded, hasMore, state == .idle else { return }
        await fetchNextPage()
    }

    func retry() async {
        guard state != .loading else { return }
        if failedPage == 0 || !hasLoaded { await reload() }
        else { await fetchNextPage() }
    }

    func cancelLoads() {
        generation += 1
        if state == .loading { state = .idle; failedPage = nil }
    }

    func invalidate() {
        generation += 1
        isInvalidated = true
        release = nil
        sections = []
        streamingPlatforms = []
        videos = []
        state = .idle
        hasMore = false
        failedPage = nil
    }

    private func fetchNextPage() async {
        guard !isInvalidated, hasCurrentViewer, hasMore, state != .loading, !Task.isCancelled else { return }
        let token = generation
        let page = nextPage
        state = .loading
        failedPage = nil
        do {
            let response = try await session.sendViewerRequest(ReleaseVideoEndpoints.videos(releaseID: releaseID, page: page), for: viewer)
            guard let rows = response.content else {
                throw AnixartError.decoding(message: "Ответ не содержит список видео", path: "video/release/\(releaseID)/\(page)")
            }
            try Task.checkCancellation()
            guard token == generation, hasCurrentViewer, !isInvalidated else { return }
            videos = Self.unique(videos + rows)
            hasMore = rows.count >= 25
            nextPage = page + 1
            state = .idle
        } catch { finishFailure(error, page: page, generation: token) }
    }

    private func finishFailure(_ error: any Error, page: Int, generation token: Int) {
        guard token == generation else { return }
        if !hasCurrentViewer || ProfileRequestFailure.isCancellation(error) { state = .idle }
        else {
            failedPage = page
            state = .failed(Paginator<ReleaseVideo>.message(for: error))
        }
    }

    private static func unique<Item: Identifiable>(_ rows: [Item]) -> [Item] {
        var seen = Set<Item.ID>()
        return rows.filter { seen.insert($0.id).inserted }
    }
}
