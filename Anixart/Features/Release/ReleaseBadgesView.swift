import SwiftUI
import AnixartKit

/// «Значки» of a release: the badges people earned for it.
@MainActor
struct ReleaseBadgesView: View {
    @Environment(AppEnvironment.self) private var env
    let releaseID: Int
    let viewer: ProfileViewerKey
    @State private var paginator: Paginator<Badge>?

    var body: some View {
        List {
            if viewer == env.session.viewerKey, let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Значков пока нет") { badge in
                    HStack(spacing: 14) {
                        CachedAsyncImage(url: AnixartURL.image(badge.imageSmallUrl ?? badge.badgeUrl), maxPixelSize: 160) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Circle().fill(.quaternary)
                        }
                        .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(badge.name ?? "Значок").font(.ax(.headline))
                            if let text = badge.description, !text.isEmpty {
                                Text(text).font(.ax(.subheadline)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Значки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let id = releaseID
                let key = viewer
                paginator = Paginator(rawPageSize: 25) { page in
                    try await session.sendViewerRequest(ReleaseEndpoints.badges(releaseID: id, page: page), for: key)
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}
