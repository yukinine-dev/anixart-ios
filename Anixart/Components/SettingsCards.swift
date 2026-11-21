import SwiftUI

/// One row of a settings group, in the card layout of the Android beta 3 settings:
/// a round tinted icon, a title and a quieter line under it.
struct SettingsRowModel: Identifiable {
    enum Kind {
        case destination(AnyView)
        case url(URL)
        case action(() -> Void)
    }

    let id = UUID()
    var icon: String
    var title: String
    var subtitle: String?
    var kind: Kind
    var isDestructive = false
}

/// A stack of rows drawn as one rounded group: large corners at the two ends, small
/// ones between, with a few points of space between the cards.
struct SettingsGroup: View {
    let rows: [SettingsRowModel]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let top: CGFloat = index == 0 ? 28 : 6
                let bottom: CGFloat = index == rows.count - 1 ? 28 : 6
                rowView(row)
                    .background(
                        Color.primary.opacity(0.08),
                        in: UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                                   bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
                    )
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: SettingsRowModel) -> some View {
        switch row.kind {
        case .destination(let destination):
            NavigationLink { destination } label: { SettingsRowLabel(row: row, showsChevron: true) }
                .buttonStyle(.plain)
        case .url(let url):
            Link(destination: url) { SettingsRowLabel(row: row, showsChevron: false) }
                .buttonStyle(.plain)
        case .action(let action):
            Button(action: action) { SettingsRowLabel(row: row, showsChevron: false) }
                .buttonStyle(.plain)
        }
    }
}

private struct SettingsRowLabel: View {
    let row: SettingsRowModel
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: row.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(row.isDestructive ? Color.red : Color.primary.opacity(0.9))
                .frame(width: 46, height: 46)
                .background((row.isDestructive ? Color.red : Theme.accent).opacity(0.28), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.ax(.title3)).foregroundStyle(row.isDestructive ? Color.red : Color.primary)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(.ax(.subheadline)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right").font(.ax(.footnote, .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
