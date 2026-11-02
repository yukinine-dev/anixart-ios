import SwiftUI

/// Shared Главная / Обзор header. Keeping one implementation also keeps both
/// notification badges and the search entry tied to the current session.
@MainActor
struct BrowsingHeader: View {
    @Environment(AppEnvironment.self) private var env
    let onSearch: () -> Void
    let onSettings: () -> Void
    var searchTitle = "Поиск аниме"

    var body: some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: onSearch) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text(searchTitle)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .glassPill()
                    // Spacer and the pill's transparent padding must be part of
                    // the button, not just the icon and the rendered text.
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browsing.search")
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.ax(.title3)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Настройки")
                NavigationLink { NotificationsView() } label: {
                    Image(systemName: "bell").font(.ax(.title3)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            if env.session.unreadNotifications > 0 {
                                Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: 3, y: -2)
                            }
                        }
                }
                .accessibilityLabel("Уведомления")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
