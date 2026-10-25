import SwiftUI

/// Centred message with an optional retry, used for every empty and failed state
/// so they look the same everywhere.
@MainActor
struct StatusMessageView: View {
    let title: String
    var message: String?
    var systemImage: String = "tray"
    var retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.ax(.headline))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button("Повторить") {
                    Task { await retry() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Renders the states of a `Paginator` in the right order: first-page spinner,
/// then failure, then empty, then content.
@MainActor
struct PaginatedContent<Item: Identifiable & Codable & Sendable, Row: View>: View {
    let paginator: Paginator<Item>
    var emptyTitle: String = "Пока ничего нет"
    var emptyMessage: String?
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        if paginator.isLoadingFirstPage {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let error = paginator.errorMessage, paginator.items.isEmpty {
            StatusMessageView(
                title: "Не удалось загрузить",
                message: error,
                systemImage: "wifi.exclamationmark",
                retry: { await paginator.reload() }
            )
        } else if paginator.items.isEmpty {
            StatusMessageView(title: emptyTitle, message: emptyMessage)
        } else {
            ForEach(paginator.items) { item in
                row(item)
                    .onAppear {
                        if item.id == paginator.items.last?.id {
                            Task { await paginator.loadNextPage() }
                        }
                    }
            }
            if paginator.state == .loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        }
    }
}

/// Horizontal carousel with a heading and an optional "see all" destination.
@MainActor
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.ax(.title3, .semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
