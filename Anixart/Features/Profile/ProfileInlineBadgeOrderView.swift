import SwiftUI
import AnixartKit

/// Android uses a pinned-only drag that can auto-save even after cancellation.
/// Keep the native in-profile mode explicit: move, then Save or Cancel.
/// This is a deliberate safety adaptation, not a claim of identical gestures.
@MainActor
struct ProfileInlineBadgeOrderView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    let account: ProfileAccountKey
    let onDone: () -> Void
    @State private var model = ProfileBadgeOrderModel()

    var body: some View {
        VStack(spacing: 16) {
            if env.session.accountKey == account {
                if model.resource.value != nil {
                    if (2...ProfileEditorRules.showcaseLimit).contains(model.badges.count) {
                        ForEach(Array(model.badges.enumerated()), id: \.element.id) { index, badge in
                            HStack {
                                ProfileBadgeImage(badge: badge, size: 52)
                                Text(badge.name ?? "Значок").font(.ax(.subheadline))
                                Spacer()
                                Button { model.move(id: badge.id, by: -1) } label: { Image(systemName: "chevron.up").padding(8) }
                                    .disabled(index == 0 || !model.canReorder).accessibilityLabel("Переместить выше")
                                Button { model.move(id: badge.id, by: 1) } label: { Image(systemName: "chevron.down").padding(8) }
                                    .disabled(index == model.badges.count - 1 || !model.canReorder).accessibilityLabel("Переместить ниже")
                            }
                        }
                        HStack {
                            Button("Отмена") { model.cancelChanges(); onDone() }
                            Spacer()
                            Button("Сохранить") { Task { await save() } }.disabled(!model.canSave)
                        }
                    } else {
                        Text("Для изменения порядка нужны два или три закреплённых значка.")
                        Button("Закрыть", action: onDone)
                    }
                } else {
                    ProfileResourceState(resource: model.resource, title: "Не удалось загрузить витрину", retry: load)
                    Button("Отмена") { model.cancelChanges(); onDone() }
                }
                if model.resource.value != nil, let error = model.resource.errorMessage {
                    StatusMessageView(title: "Не удалось обновить витрину", message: error, retry: load)
                }
                ProfileSaveError(message: model.errorMessage)
            } else { ProfileAccountNotice(account: account) }
        }
        .padding().disabled(model.isSaving || env.session.accountKey != account)
        .task { if model.resource.value == nil { await load() } }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { model.reset() }
        }
    }

    private func load() async {
        await model.load(profileID: profileID, account: account, session: env.session)
    }

    private func save() async {
        if await model.save(profileID: profileID, account: account, session: env.session) { onDone() }
    }
}
