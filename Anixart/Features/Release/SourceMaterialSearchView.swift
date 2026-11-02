import SwiftUI
import AnixartKit

/// Release fact links use scoped release search, not web help or filter/{page}.
/// Opening a link is read-only
/// and does not replace the user's query/filter in Home or Catalogue.
@MainActor
struct SourceMaterialSearchView: View {
    @Environment(AppEnvironment.self) private var env
    let query: String
    let scope: SearchScope
    let title: String
    let viewer: ProfileViewerKey
    @State private var model: CatalogViewModel?

    init(source: SourceMaterial, viewer: ProfileViewerKey) {
        self.init(query: source.rawValue, scope: .sourceMaterial, title: source.title, viewer: viewer)
    }

    init(query: String, scope: SearchScope, title: String, viewer: ProfileViewerKey) {
        self.query = query
        self.scope = scope
        self.title = title
        self.viewer = viewer
    }

    var body: some View {
        VStack(spacing: 0) {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey {
                if let model, model.hasCurrentViewer { ReleaseSearchResultsView(model: model) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewer == env.session.viewerKey else { return }
            if model == nil {
                model = CatalogViewModel(session: env.session, query: query, searchScope: scope)
            }
            await model?.search()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model = nil }
        }
    }
}
