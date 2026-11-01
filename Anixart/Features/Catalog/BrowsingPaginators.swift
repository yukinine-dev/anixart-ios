import Foundation
import AnixartKit

/// These browsing APIs report placeholder/last-index metadata. Their verified
/// raw page size is 25; defaults for profile/bookmark paginators stay unchanged.
@MainActor
enum BrowsingPaginators {
    static func related(relatedID: Int, viewer: ProfileViewerKey, session: SessionController) -> Paginator<Release> {
        Paginator(rawPageSize: 25) { page in
            try await session.sendViewerRequest(ReleaseEndpoints.related(relatedID: relatedID, page: page), for: viewer)
        }
    }

    static func publicCollections(viewer: ProfileViewerKey, session: SessionController) -> Paginator<ReleaseCollection> {
        Paginator(rawPageSize: 25) { page in
            try await session.sendViewerRequest(CollectionEndpoints.all(page: page, previousPage: max(0, page - 1)), for: viewer)
        }
    }

    static func releaseCollections(releaseID: Int, viewer: ProfileViewerKey, session: SessionController) -> Paginator<ReleaseCollection> {
        Paginator(rawPageSize: 25) { page in
            try await session.sendViewerRequest(CollectionEndpoints.containing(releaseID: releaseID, page: page), for: viewer)
        }
    }

    static func collectionReleases(collectionID: Int, viewer: ProfileViewerKey, session: SessionController) -> Paginator<Release> {
        Paginator(rawPageSize: 25) { page in
            try await session.sendViewerRequest(CollectionEndpoints.releases(collectionID: collectionID, page: page), for: viewer)
        }
    }
}
