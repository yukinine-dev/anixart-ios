import SwiftUI

/// "Выберите плеер": the three options, the "Спрашивать всегда" checkbox and
/// Продолжить, as the Android dialog lays them out.
@MainActor
struct PlayerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preferences: PlaybackPreferences
    /// False when nothing was found but the hosting's own page, which the
    /// embedded and external players cannot do anything with.
    let supportsDirectPlayback: Bool
    /// Where the stream came from, when it is not the hosting the user picked.
    let streamSourceName: String?
    /// A hosting of the same voice-over that does hand over a stream, if there
    /// is one. Naming it beats telling the user playback is simply impossible.
    let alternativeSourceName: String?
    let onContinue: (PlayerChoice) -> Void

    @State private var selection: PlayerChoice = .web
    @State private var alwaysAsk = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Выберите плеер")
                    .font(.ax(.title2, .medium))
                // Anixart's hostings serve player pages, so a stream that was
                // found came from somewhere else; say where before playing it.
                if supportsDirectPlayback, let streamSourceName {
                    Text("Видео найдено на «\(streamSourceName)»")
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }

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
                Text(available ? option.summary : unavailableReason)
                    .font(.ax(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                // Theme.accent is a Color and .quaternary is a hierarchical
                // style, so the two sides need erasing to one type.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selection == option ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary),
                        lineWidth: 1
                    )
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

    private var unavailableReason: String {
        if let alternativeSourceName {
            return "Источник отдаёт страницу плеера, а не видео. Видео есть у источника «\(alternativeSourceName)» — закройте и выберите его."
        }
        return "Источник отдаёт страницу плеера, а не видео — его может показать только Веб-плеер"
    }
}
