import Foundation
import AnixartKit

/// Page-zero search metadata has its own generation: a retired refresh must not
/// replace the channel/blog previews while the paginator rejects its old articles.
@MainActor
@Observable
final class FeedSearchMetadata {
    private(set) var channels: PageableResponse<Channel>?
    private(set) var blogs: PageableResponse<Channel>?
    private(set) var tags: [String] = []
    private(set) var hasLoaded = false
    private var generation = 0

    func begin() -> Int { generation += 1; return generation }
    func adopt(_ response: FeedSearchResponse, generation expected: Int) {
        guard generation == expected, !Task.isCancelled else { return }
        channels = unique(response.channels)
        blogs = unique(response.blogs)
        tags = response.tags?.items ?? []
        hasLoaded = true
    }

    private func unique(_ source: PageableResponse<Channel>?) -> PageableResponse<Channel>? {
        guard var source else { return nil }
        var seen = Set<Int>()
        source.content = source.content?.filter { seen.insert($0.id).inserted }
        return source
    }
}

@MainActor
@Observable
final class FeedSearchModel {
    let query: String
    let viewer: ProfileViewerKey
    let metadata: FeedSearchMetadata
    let articles: Paginator<Article>
    private let session: SessionController

    init(query: String, session: SessionController) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query
        self.session = session
        let viewer = session.viewerKey
        self.viewer = viewer
        let metadata = FeedSearchMetadata()
        self.metadata = metadata
        articles = Paginator(rawPageSize: 25) { page in
            let revision: Int?
            if page == 0 { revision = await metadata.begin() } else { revision = nil }
            let response = try await session.sendViewerRequest(FeedEndpoints.search(query, page: page), for: viewer)
            guard let articles = response.articles else {
                throw AnixartError.decoding(message: "Сервер не вернул результаты поиска", path: "search/feed/\(page)")
            }
            let validated = try await FeedPageValidation.articles(articles, path: "search/feed/\(page)")
            if page == 0 {
                if let channels = response.channels { _ = try await FeedPageValidation.channels(channels, path: "search/feed/0:channels") }
                if let blogs = response.blogs { _ = try await FeedPageValidation.channels(blogs, path: "search/feed/0:blogs") }
                if let revision { await metadata.adopt(response, generation: revision) }
            }
            return validated
        }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }

    func load(debounce: Bool = true) async {
        guard hasCurrentViewer, !query.isEmpty else { return }
        if debounce { do { try await Task.sleep(for: .milliseconds(300)) } catch { return } }
        guard hasCurrentViewer, !Task.isCancelled else { return }
        await articles.loadFirstPageIfNeeded()
    }

    func reload() async { if hasCurrentViewer, !query.isEmpty { await articles.reload() } }
}
