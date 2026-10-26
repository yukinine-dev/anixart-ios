import SwiftUI

/// "Выберите плеер": the three options, the "Спрашивать всегда" checkbox and
/// Продолжить, as the Android dialog lays them out.
@MainActor
struct PlayerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preferences: PlaybackPreferences
    /// `nil` when the episode has no direct stream, which the embedded and
    /// external players both need; that option is then shown as unavailable
    /// rather than hidden, so the list does not change shape between episodes.
    let supportsDirectPlayback: Bool
    let onContinue: (PlayerChoice) -> Void

    @State private var selection: PlayerChoice = .web
    @State private var alwaysAsk = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Выберите плеер")
                .font(.ax(.title2, .medium))

            VStack(spacing: 12) {
                ForEach(PlayerChoice.allCases) { option in
                    optionRow(option)
                }
            }

            Divider()

            Button {
                alwaysAsk.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: alwaysAsk ? "checkmark.square.fill" : "square")
                        .font(.ax(.title3))
                        .foregroundStyle(alwaysAsk ? Theme.accent : .secondary)
                    Text("Спрашивать всегда").font(.ax(.title3))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                Button("Продолжить") {
                    preferences.save(choice: selection, alwaysAsk: alwaysAsk)
                    onContinue(selection)
                    dismiss()
                }
                .font(.ax(.title3, .medium))
                .foregroundStyle(.primary)
                .disabled(!isAvailable(selection))
            }
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .onAppear {
            selection = isAvailable(preferences.choice) ? preferences.choice : .web
            alwaysAsk = preferences.alwaysAsk
        }
    }

    private func optionRow(_ option: PlayerChoice) -> some View {
        let available = isAvailable(option)
        return Button {
            guard available else { return }
            selection = option
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title).font(.ax(.title3, .medium))
                Text(available ? option.summary : "Этот источник отдаёт только страницу плеера")
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selection == option ? Theme.accent : .quaternary, lineWidth: 1)
            }
            .opacity(available ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }

    /// Only the web player can show a hosting's own page; the other two need a
    /// stream they can hand to AVFoundation.
    private func isAvailable(_ option: PlayerChoice) -> Bool {
        option == .web || supportsDirectPlayback
    }
}
