import SwiftUI
import AnixartKit

/// ReleaseFragment's source#<label> route is a scoped release search (searchBy=5),
/// not source-specific web help and not filter/{page}. Opening it is read-only
/// and does not replace the user's query/filter in Home or Catalogue.
@MainActor
struct SourceMaterialSearchView: View {
    @Environment(AppEnvironment.self) private var env
    let source: SourceMaterial
    let viewer: ProfileViewerKey
    @State private var model: CatalogViewModel?

    var body: some View {
        VStack(spacing: 0) {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey {
                if let model, model.hasCurrentViewer { ReleaseSearchResultsView(model: model) }
                else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewer == env.session.viewerKey else { return }
            if model == nil {
                model = CatalogViewModel(session: env.session, query: source.rawValue, searchScope: .sourceMaterial)
            }
            await model?.search()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { model = nil }
        }
    }
}
