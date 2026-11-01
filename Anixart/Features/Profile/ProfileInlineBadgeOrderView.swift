import SwiftUI
import AnixartKit

/// The audit confirms an in-profile mode and the >1 pinned gate, but not a
/// working Android drag gesture. Explicit move controls keep this mode usable
/// without presenting an unverified gesture as Android parity.
@MainActor
struct ProfileInlineBadgeOrderView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    let account: ProfileAccountKey
    let onDone: () -> Void
    @State private var resource = ProfileResource<ProfileBadgeSectionsResponse>()
    @State private var badges: [Badge] = []
    @State private var originalIDs: [Int] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if env.session.accountKey == account {
                if resource.value != nil {
                    if (2...ProfileEditorRules.showcaseLimit).contains(badges.count) {
                        ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                            HStack {
                                ProfileBadgeImage(badge: badge, size: 52)
                                Text(badge.name ?? "Значок").font(.ax(.subheadline))
                                Spacer()
                                Button { badges.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up").padding(8) }
                                    .disabled(index == 0).accessibilityLabel("Переместить выше")
                                Button { badges.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down").padding(8) }
                                    .disabled(index == badges.count - 1).accessibilityLabel("Переместить ниже")
                            }
                        }
                        HStack {
                            Button("Отмена", action: onDone)
                            Spacer()
                            Button("Сохранить") { Task { await save() } }.disabled(badges.map(\.id) == originalIDs)
                        }
                    } else {
                        Text("Для изменения порядка нужны два или три закреплённых значка.")
                        Button("Закрыть", action: onDone)
                    }
                } else { ProfileResourceState(resource: resource, title: "Не удалось загрузить витрину", retry: load) }
                ProfileSaveError(message: errorMessage ?? resource.errorMessage)
            } else { ProfileAccountNotice(account: account) }
        }
        .padding().disabled(isSaving || env.session.accountKey != account)
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if account != current { resource.reset(); badges = []; originalIDs = []; errorMessage = nil }
        }
    }

    private func load() async {
        guard account.profileID == profileID else { return }
        if let response = await resource.load({ try await env.session.sendAccountRequest(ProfileBadgeEndpoints.sections(profileID: profileID), for: account) }) {
            badges = response.showcased ?? []
            originalIDs = badges.map(\.id)
        }
    }

    private func save() async {
        guard !isSaving, env.session.accountKey == account, (2...ProfileEditorRules.showcaseLimit).contains(badges.count),
              Set(badges.map(\.id)) == Set(originalIDs), badges.map(\.id) != originalIDs else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.reorder(ids: badges.map(\.id)), for: account)
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account { onDone() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}
