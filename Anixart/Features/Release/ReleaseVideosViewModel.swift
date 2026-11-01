import Foundation
import AnixartKit

@MainActor
@Observable
final class ReleaseVideosViewModel {
    let viewer: ProfileViewerKey
    let paginator: Paginator<ReleaseVideo>

    init(releaseID: Int, categoryID: Int? = nil, viewer: ProfileViewerKey, session: SessionController) {
        self.viewer = viewer
        paginator = Paginator(rawPageSize: 25) { page in
            let endpoint = categoryID.map {
                ReleaseVideoEndpoints.videos(releaseID: releaseID, categoryID: $0, page: page)
            } ?? ReleaseVideoEndpoints.videos(releaseID: releaseID, page: page)
            return try await session.sendViewerRequest(endpoint, for: viewer)
        }
    }
}
