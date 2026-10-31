import Foundation
import AnixartKit

/// The release and viewer are fixed when the sheet opens. Selecting a collection
/// closes it only after the server confirms the addition for that account.
@MainActor
@Observable
final class AddToCollectionViewModel {
    let viewer: ProfileViewerKey
    private let releaseID: Int
    private let session: SessionController
    private(set) var paginator: Paginator<ReleaseCollection>?
    private(set) var addingCollectionID: Int?
    private(set) var errorMessage: String?

    init(releaseID: Int, viewer: ProfileViewerKey, session: SessionController) {
        self.releaseID = releaseID
        self.viewer = viewer
        self.session = session
        if let account = viewer.account {
            paginator = Paginator { page in
                try await session.sendAccountRequest(CollectionEndpoints.byProfile(account.profileID, page: page), for: account)
            }
        }
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var isSignedIn: Bool { hasCurrentViewer && viewer.account != nil }
    var isAdding: Bool { addingCollectionID != nil }

    func invalidate() {
        paginator = nil
        errorMessage = nil
        addingCollectionID = nil
    }

    func dismissError() { errorMessage = nil }

    @discardableResult
    func add(to collection: ReleaseCollection) async -> Bool {
        guard hasCurrentViewer, !Task.isCancelled, !isAdding, releaseID > 0, collection.id > 0 else { return false }
        guard let account = viewer.account else { session.promptSignIn(); return false }
        guard collection.creator == nil || collection.creator?.id == account.profileID else {
            errorMessage = "Можно добавлять релизы только в свои коллекции."
            return false
        }
        addingCollectionID = collection.id
        errorMessage = nil
        defer { addingCollectionID = nil }
        do {
            let response = try await session.sendAccountRequest(
                CollectionEndpoints.addRelease(collectionID: collection.id, releaseID: releaseID), for: account
            )
            guard response.code == 0 else {
                throw AnixartError.decoding(message: "Сервер не подтвердил добавление в коллекцию", path: "collectionMy/release/add")
            }
            await session.refreshProfile(for: account)
            return hasCurrentViewer && !Task.isCancelled
        } catch {
            if hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) { errorMessage = Self.message(for: error) }
            return false
        }
    }

    private static func message(for error: any Error) -> String {
        guard let api = error as? AnixartError, case .api(let code, _) = api else {
            return Paginator<ReleaseCollection>.message(for: error)
        }
        // Constants from the installed APK's ReleaseAddCollectionResponse.
        switch code {
        case 2: return "Коллекция не найдена. Обновите список."
        case 3: return "Можно добавлять релизы только в свои коллекции."
        case 4: return "Этот релиз недоступен для добавления."
        case 5: return "Релиз уже есть в этой коллекции."
        case 6: return "Коллекция удалена. Обновите список."
        case 7: return "В коллекции достигнут лимит релизов."
        default: return Paginator<ReleaseCollection>.message(for: error)
        }
    }
}
