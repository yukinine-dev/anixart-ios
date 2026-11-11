import SwiftUI
import AnixartKit

/// Picks which of the five watch lists a release belongs to.
///
/// The lists are mutually exclusive server-side -- adding to one removes it from
/// whichever it was in -- so this is a single choice, not a set of toggles.
@MainActor
struct ListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let current: ProfileListStatus?
    let onSelect: (ProfileListStatus?) -> Void

    /// Android's order: not watching, a divider, then the five lists.
    private let order: [ProfileListStatus] = [.watching, .plan, .completed, .holdOn, .dropped]

    var body: some View {
        VStack(spacing: 0) {
            row(title: "Не смотрю", color: .gray, selected: current == nil) { onSelect(nil) }
            Divider().padding(.vertical, 6)
            ForEach(order, id: \.self) { status in
                row(title: status.title, color: Theme.listColor(status), selected: status == current) {
                    onSelect(status)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }

    private func row(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 18) {
                Circle().fill(color).frame(width: 12, height: 12)
                Text(title).font(.ax(.title3))
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.ax(.headline)).foregroundStyle(color)
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 54)
            .background(selected ? color.opacity(0.28) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

/// Five-star rating with the vote distribution underneath.
@MainActor
struct RatingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let current: Int?
    /// Carries `vote_1_count` ... `vote_5_count` for the histogram.
    let distribution: Release
    let onVote: (ReleaseVote) -> Void
    let onRemove: () -> Void

    private var counts: [Int] {
        [
            distribution.vote1Count ?? 0,
            distribution.vote2Count ?? 0,
            distribution.vote3Count ?? 0,
            distribution.vote4Count ?? 0,
            distribution.vote5Count ?? 0
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.section) {
                HStack(spacing: 10) {
                    ForEach(ReleaseVote.allCases) { score in
                        Button {
                            onVote(score)
                            dismiss()
                        } label: {
                            Image(systemName: (current ?? 0) >= score.rawValue ? "star.fill" : "star")
                                .font(.system(size: 30))
                                .foregroundStyle((current ?? 0) >= score.rawValue ? Theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top)

                VStack(spacing: 6) {
                    let total = max(counts.reduce(0, +), 1)
                    ForEach(Array(counts.enumerated()).reversed(), id: \.offset) { index, count in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.ax(.caption).monospacedDigit())
                                .frame(width: 14)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.quaternary)
                                    Capsule()
                                        .fill(Theme.ratingColor(Double(index + 1)))
                                        .frame(width: geometry.size.width * CGFloat(count) / CGFloat(total))
                                }
                            }
                            .frame(height: 8)
                            Text(Format.count(count))
                                .font(.ax(.caption2).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal)

                if let current, (1...5).contains(current) {
                    Button("Убрать оценку", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }

                Spacer()
            }
            .navigationTitle("Оценка")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
