import SwiftUI
import AnixartKit

/// Editorial banners supply an ID, not a collection object. Read the confirmed
/// collection/{id} endpoint before showing its existing detail screen.
@MainActor
struct CollectionByIDView: View {
    @Environment(AppEnvironment.self) private var env
    let collectionID: Int
    let viewer: ProfileViewerKey
    @State private var resource = ProfileResource<ReleaseCollection>()

    var body: some View {
        Group {
            if viewer != env.session.viewerKey {
                ProfileViewerNotice(viewer: viewer)
            } else if let collection = resource.value {
                CollectionDetailView(collection: collection, viewer: viewer)
            } else {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить коллекцию", retry: load)
            }
        }
        .navigationTitle(resource.value?.displayTitle ?? "Коллекция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { if resource.value == nil { await load() } }
        .onChange(of: env.session.viewerKey) { _, current in if current != viewer { resource.reset() } }
    }

    private func load() async {
        guard viewer == env.session.viewerKey else { return }
        await resource.load {
            let response = try await env.session.sendViewerRequest(CollectionEndpoints.collection(id: collectionID), for: viewer)
            guard let collection = response.collection, collection.id == collectionID else {
                throw AnixartError.decoding(message: "Ответ не содержит коллекцию", path: "collection/\(collectionID)")
            }
            return collection
        }
    }
}
