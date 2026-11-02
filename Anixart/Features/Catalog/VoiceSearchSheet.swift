import SwiftUI
import UIKit

/// A dismissal callback belongs to the presentation that created its binding,
/// not whatever query/viewer may now have a newer voice sheet.
@MainActor
func voiceSearchPresentationBinding(_ model: CatalogViewModel?) -> Binding<Bool> {
    let presented = model?.voiceInput
    return Binding(get: { presented != nil && model?.voiceInput === presented }, set: { showing in
        if !showing, let presented { model?.closeVoiceSearch(ifCurrent: presented) }
    })
}

@MainActor
struct ReleaseSearchInputButton: View {
    let model: CatalogViewModel

    var body: some View {
        if model.query.isEmpty {
            Button { model.beginVoiceSearch() } label: { Image(systemName: "mic") }
                .accessibilityLabel("Голосовой поиск")
                .disabled(!model.isVoiceSearchAvailable)
        } else {
            Button { model.query = "" } label: { Image(systemName: "xmark.circle") }
                .accessibilityLabel("Очистить поиск")
                .disabled(!model.hasCurrentViewer)
        }
    }
}

@MainActor
struct VoiceSearchSheet: View {
    @Environment(\.openURL) private var openURL
    let model: VoiceSearchModel
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    status
                    if !model.transcript.isEmpty {
                        Text(model.transcript).font(.ax(.title3)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.state == .listening {
                        Text("Произнесите название аниме. Нажмите «Найти», чтобы использовать распознанный текст, или «Отмена», чтобы ничего не менять.")
                            .font(.ax(.subheadline)).foregroundStyle(.secondary)
                        Button("Найти") { model.useTranscript() }
                            .font(.ax(.headline)).buttonStyle(.borderedProminent)
                            .disabled(!model.canUseTranscript)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Голосовой поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена", role: .cancel, action: onCancel) }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear(perform: onCancel)
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle, .starting:
            ProgressView("Подготовка голосового ввода…").font(.ax(.subheadline))
        case .authorizing(let permission):
            ProgressView(permission == .speech ? "Разрешение на распознавание речи…" : "Разрешение на микрофон…")
                .font(.ax(.subheadline))
        case .listening:
            Label("Слушаю…", systemImage: "mic.fill").font(.ax(.title3, .medium))
                .accessibilityAddTraits(.updatesFrequently)
        case .failed(let problem):
            Text(problem.message).font(.ax(.subheadline))
            if problem.offersSettings {
                Button("Открыть настройки iOS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }.font(.ax(.subheadline))
            }
            Button("Попробовать ещё раз", action: onRetry).font(.ax(.headline)).buttonStyle(.bordered)
        case .completed:
            Text("Текст добавлен в поиск").font(.ax(.subheadline))
        case .cancelled:
            Text("Голосовой ввод отменён").font(.ax(.subheadline)).foregroundStyle(.secondary)
        }
    }
}
