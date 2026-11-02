import SwiftUI
import UIKit
import AnixartKit

enum ProfileReputationCopy {
    static func foreign(login: String, score: Int) -> String {
        "Уровень репутации пользователя \(login): \(score). Это репутация владельца этого профиля."
    }
}

@MainActor
struct ProfileReputationBadge: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let login: String
    let score: Int
    let isOwn: Bool
    let viewer: ProfileViewerKey?
    @Binding var infoPresentation: ProfileInfoPresentation?
    let onOwnInfo: () -> Void

    var body: some View {
        Button {
            guard viewer == env.session.viewerKey else { return }
            if infoPresentation != nil { infoPresentation = nil; return }
            if isOwn { onOwnInfo() }
            else {
                infoPresentation = ProfileInfoPresentation(source: .reputation, kind: ProfileInfoPresentationPolicy.kind(
                    horizontal: horizontalSizeClass, vertical: verticalSizeClass, dynamicType: dynamicTypeSize))
            }
        } label: {
            Text("\(score)")
                .font(.ax(.subheadline, .medium)).monospacedDigit()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(Theme.listColor(.watching))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.listColor(.watching), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Уровень репутации \(login): \(score)")
        .profileInfoPresentation($infoPresentation, source: .reputation, title: "Репутация пользователя") {
            Text(ProfileReputationCopy.foreign(login: login, score: score))
                .font(.ax(.body)).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { infoPresentation = nil } }
    }
}

/// Published contact methods are not a guessed Anixart direct-message endpoint.
/// Nothing is sent or copied until the user chooses a public contact explicitly.
@MainActor
struct ProfileContactButton: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: Profile
    let viewer: ProfileViewerKey?
    @Binding var infoPresentation: ProfileInfoPresentation?
    @State private var copiedDiscord = false

    private var contacts: [(name: String, icon: String, value: String)] {
        guard profile.isSocialHidden != true else { return [] }
        return [("VK", "person.2", profile.vkPage), ("Telegram", "paperplane", profile.tgPage),
                ("Discord", "bubble.left.and.bubble.right", profile.discordPage), ("TikTok", "music.note", profile.ttPage)]
            .compactMap { name, icon, value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
                return (name, icon, value)
            }
    }

    var body: some View {
        Button {
            guard viewer == env.session.viewerKey else { return }
            if infoPresentation != nil { infoPresentation = nil; return }
            copiedDiscord = false
            infoPresentation = ProfileInfoPresentation(source: .contacts, kind: ProfileInfoPresentationPolicy.kind(
                horizontal: horizontalSizeClass, vertical: verticalSizeClass, dynamicType: dynamicTypeSize))
        } label: {
            Image(systemName: "bubble.left")
                .font(.ax(.headline)).foregroundStyle(.secondary)
                .frame(width: 46, height: 46)
                .background(Theme.raisedSurface, in: Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Связаться")
        .disabled(viewer != env.session.viewerKey)
        .profileInfoPresentation($infoPresentation, source: .contacts, title: "Контакты") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Связаться с \(profile.displayLogin)").font(.ax(.headline))
                    .fixedSize(horizontal: false, vertical: true)
                if contacts.isEmpty {
                    Text(profile.isSocialHidden == true ? "Пользователь скрыл публичные контакты." : "Пользователь не указал публичные контакты.")
                        .font(.ax(.subheadline)).foregroundStyle(.secondary)
                } else {
                    ForEach(contacts, id: \.name) { contact in
                        Button {
                            guard viewer == env.session.viewerKey else { return }
                            if let url = ProfileSocialAddress.url(contact.value, service: contact.name) {
                                infoPresentation = nil
                                openURL(url)
                            }
                            else if contact.name == "Discord" { UIPasteboard.general.string = contact.value; copiedDiscord = true }
                        } label: {
                            Label(contact.name, systemImage: contact.icon).font(.ax(.body))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if copiedDiscord { Text("Имя Discord скопировано").font(.ax(.caption)).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { infoPresentation = nil; copiedDiscord = false } }
    }
}
