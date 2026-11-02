import SwiftUI
import AnixartKit

enum ProfileAvatarCommand: String, CaseIterable, Hashable {
    case open, edit, delete

    var title: String {
        switch self {
        case .open: return "Открыть"
        case .edit: return "Изменить"
        case .delete: return "Удалить"
        }
    }

    var systemImage: String {
        switch self {
        case .open: return "photo"
        case .edit: return "pencil"
        case .delete: return "trash"
        }
    }
}

/// Keep the native menu's source bounds at the photo, not the padded identity
/// header. The caller routes commands; opening the menu performs no account write.
@MainActor
struct ProfileAvatarControl: View {
    static let size: CGFloat = 112
    let profile: Profile
    let isOwnProfile: Bool
    let onCommand: (ProfileAvatarCommand) -> Void

    var menuCommands: [ProfileAvatarCommand] {
        guard isOwnProfile else { return [] }
        return profile.avatarURL == nil ? [.edit] : [.open, .edit, .delete]
    }

    var body: some View {
        Group {
            if isOwnProfile {
                Menu {
                    ForEach(menuCommands, id: \.self) { command in
                        Button(role: command == .delete ? .destructive : nil) {
                            onCommand(command)
                        } label: {
                            Label(command.title, systemImage: command.systemImage)
                        }
                    }
                } label: { photo }
                .menuIndicator(.hidden)
                .accessibilityHint("Открывает меню фото профиля")
            } else {
                Button { onCommand(.open) } label: { photo }
                    .disabled(profile.avatarURL == nil)
                    .accessibilityHint("Открывает фото профиля")
            }
        }
        .buttonStyle(.plain)
        .frame(width: Self.size, height: Self.size)
        .fixedSize()
        .contentShape(Circle())
        .accessibilityLabel("Фото профиля")
        .accessibilityIdentifier("profile.avatar")
    }

    private var photo: some View {
        Avatar(url: profile.avatarURL, size: Self.size, isOnline: profile.isOnline ?? false)
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
    }
}
