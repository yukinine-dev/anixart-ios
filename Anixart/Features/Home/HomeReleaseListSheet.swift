import SwiftUI
import AnixartKit

/// The browsing overflow remains a list picker, but it no longer dismisses on a
/// failed/unconfirmed request or silently ignores the remove-list choice.
@MainActor
struct HomeReleaseListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let release: Release
    let model: ReleaseFeedModel

    private var current: ProfileListStatus? {
        if let selected = model.actionRelease, selected.id == release.id { return selected.listStatus }
        if let row = model.paginator.items.first(where: { $0.id == release.id }) { return row.listStatus }
        return release.listStatus
    }

    var body: some View {
        NavigationStack {
            List {
                ProfileViewerNotice(viewer: model.viewer)
                if model.hasCurrentViewer {
                    Button { select(nil) } label: {
                        HStack {
                            Text("Не смотрю")
                            Spacer()
                            if current == nil { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                        .font(.ax(.body)).foregroundStyle(.primary)
                    }
                    .disabled(model.isPerformingAction || model.isLoadingActionRelease)
                    ForEach(ProfileListStatus.allCases) { status in
                        Button { select(status) } label: {
                            HStack {
                                Label(status.title, systemImage: status.systemImage)
                                Spacer()
                                if status == current { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                            .font(.ax(.body))
                            .foregroundStyle(.primary)
                        }
                        .disabled(model.isPerformingAction || model.isLoadingActionRelease)
                    }
                    if model.isPerformingAction { ProgressView().frame(maxWidth: .infinity) }
                    if let error = model.actionError {
                        Text(error).font(.ax(.subheadline)).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Выберите статус просмотра")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(model.isPerformingAction)
        .onAppear { model.dismissActionError() }
    }

    private func select(_ status: ProfileListStatus?) {
        Task { if await model.setList(status, releaseID: release.id) { dismiss() } }
    }
}
