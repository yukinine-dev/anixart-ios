import Foundation
import AnixartKit

@MainActor
@Observable
final class NotificationsModel {
    private(set) var viewer: ProfileViewerKey?
    private(set) var paginator: Paginator<AnixartNotification>?
    private(set) var readError: String?
    var filter: NotificationFeedFilter = .all
    private var loadedFilter: NotificationFeedFilter?
    private var readGeneration = 0

    var readCandidates: [Int] {
        guard loadedFilter == filter, readError == nil, paginator?.state == .idle else { return [] }
        return paginator?.items.filter { $0.base.isNew == true }.map(\.id) ?? []
    }

    func invalidate(for current: ProfileViewerKey) {
        guard let viewer, viewer != current else { return }
        paginator = nil
        readError = nil
    }

    func load(session: SessionController) async {
        if viewer == nil { viewer = session.viewerKey }
        guard let viewer, viewer == session.viewerKey, viewer.account != nil else { return }
        if paginator == nil || loadedFilter != filter {
            let filter = self.filter
            paginator = Paginator { page in
                let endpoint = NotificationEndpoints.feed(filter, page: page)
                let response = try await session.sendViewerRequest(endpoint, for: viewer)
                guard response.code == AnixartStatus.successful, let items = response.content,
                      items.allSatisfy({ $0.base.id != nil }) else {
                    throw AnixartError.decoding(message: "Сервер не вернул список уведомлений", path: endpoint.path)
                }
                return response
            }
            loadedFilter = filter
            readError = nil
        }
        await paginator?.loadFirstPageIfNeeded()
    }

    /// Android's 1000 ms delay only runs after a loaded page contains new items.
    /// Failed loads and failed read acknowledgements never clear the badge.
    func markReadIfNeeded(session: SessionController, delayed: Bool = true, retrying: Bool = false) async {
        guard retrying || readError == nil, loadedFilter == filter, let list = paginator, list.state == .idle,
              list.items.contains(where: { $0.base.isNew == true }),
              let viewer, viewer == session.viewerKey, let account = viewer.account else { return }
        readGeneration += 1
        let generation = readGeneration
        do {
            if delayed { try await Task.sleep(for: .seconds(1)) }
            try Task.checkCancellation()
            guard generation == readGeneration, viewer == session.viewerKey, paginator === list, list.state == .idle,
                  list.items.contains(where: { $0.base.isNew == true }) else { return }
            try await session.markNotificationsRead(for: account)
            guard generation == readGeneration, viewer == session.viewerKey, paginator === list else { return }
            for item in list.items { list.update(item.markedRead()) }
            readError = nil
        } catch {
            if generation == readGeneration, viewer == session.viewerKey, !ProfileRequestFailure.isCancellation(error) {
                readError = Paginator<Release>.message(for: error)
            }
        }
    }

    func retryRead(session: SessionController) async {
        await markReadIfNeeded(session: session, delayed: false, retrying: true)
    }
}
