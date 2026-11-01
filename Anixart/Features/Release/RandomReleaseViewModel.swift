import Foundation
import AnixartKit

@MainActor
@Observable
final class RandomReleaseViewModel {
    let viewer: ProfileViewerKey
    private let session: SessionController
    private let resource = ProfileResource<Release>()

    init(session: SessionController) {
        self.session = session
        self.viewer = session.viewerKey
    }

    var hasCurrentViewer: Bool { viewer == session.viewerKey }
    var release: Release? { hasCurrentViewer ? resource.value : nil }
    var errorMessage: String? { hasCurrentViewer ? resource.errorMessage : nil }
    var isLoading: Bool { resource.isLoading }

    func invalidate() { resource.reset() }

    func load() async {
        guard hasCurrentViewer, !Task.isCancelled else { return }
        await resource.load {
            let response = try await session.sendViewerRequest(ReleaseEndpoints.random(extended: true), for: viewer)
            guard let release = response.release, release.id > 0 else {
                throw AnixartError.decoding(message: "Ответ не содержит случайный релиз", path: "release/random")
            }
            return release
        }
    }
}
