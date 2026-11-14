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

    /// `nil` is «Не смотрю». The picked option moves up into the highlighted top slot
    /// and the previous one drops into the list, so «Не смотрю» is no longer a fixed
    /// row of its own.
    @State private var picked: ProfileListStatus?
    @State private var didPick = false
    @State private var sheetHeight: CGFloat = 400
    @Namespace private var slots

    private let options: [ProfileListStatus?] = [nil, .watching, .plan, .completed, .holdOn, .dropped]

    init(current: ProfileListStatus?, onSelect: @escaping (ProfileListStatus?) -> Void) {
        self.current = current
        self.onSelect = onSelect
        _picked = State(initialValue: current)
    }

    var body: some View {
        VStack(spacing: 0) {
            row(picked, isTop: true)
            Divider().padding(.vertical, 6)
            ForEach(options.filter { $0 != picked }, id: \.self) { status in
                row(status, isTop: false)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { Color.clear.preference(key: PickerHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(PickerHeightKey.self) { sheetHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        // Sized to the rows, so nothing is left empty below «Брошено».
        .presentationDetents([.height(sheetHeight + 20)])
        .presentationDragIndicator(.visible)
    }

    private func title(_ status: ProfileListStatus?) -> String { status?.title ?? "Не смотрю" }
    private func color(_ status: ProfileListStatus?) -> Color { status.map { Theme.listColor($0) } ?? .gray }

    private func row(_ status: ProfileListStatus?, isTop: Bool) -> some View {
        Button {
            guard !didPick else { return }
            didPick = true
            if status != picked {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { picked = status }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                onSelect(status)
                dismiss()
            }
        } label: {
            HStack(spacing: 18) {
                Circle().fill(color(status)).frame(width: 12, height: 12)
                Text(title(status)).font(.ax(.title3))
                Spacer()
                if isTop {
                    Image(systemName: "checkmark").font(.ax(.headline)).foregroundStyle(color(status))
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 54)
            .background(isTop ? color(status).opacity(0.28) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .matchedGeometryEffect(id: status, in: slots)
    }
}

private struct PickerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
