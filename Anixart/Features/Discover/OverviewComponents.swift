import SwiftUI
import AnixartKit

/// Header of the main sections in the new Android beta: logo on the left,
/// settings, notifications and the viewer's avatar on the right. It replaces the
/// search field; search is a separate round button next to the tab bar.
/// The avatar opens the profile (there is no Профиль tab any more); a long press
/// shows «Мои друзья» and «Редактировать».
@MainActor
struct OverviewHeader: View {
    @Environment(AppEnvironment.self) private var env
    let onSettings: () -> Void
    var onSearch: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            if let onSearch {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Поиск")
            }
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Настройки")
            NavigationLink { NotificationsView() } label: {
                Image(systemName: "bell")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if env.session.unreadNotifications > 0 {
                            Circle().fill(Theme.accent).frame(width: 9, height: 9).offset(x: -8, y: 8)
                        }
                    }
            }
            .accessibilityLabel("Уведомления")
            avatar
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var avatar: some View {
        NavigationLink { ProfileTabView() } label: {
            Avatar(url: env.session.profile?.avatarURL, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    // A temporarily banned account shows a red mark on its avatar.
                    if env.session.profile?.isBanned == true {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Theme.newBadge)
                            .offset(x: 4, y: 4)
                    }
                }
        }
        .contextMenu {
            if let id = env.session.currentProfileID {
                NavigationLink { FriendsView(profileID: id) } label: { Label("Мои друзья", systemImage: "person.2") }
                NavigationLink { ProfileEditorView(profileID: id, account: env.session.accountKey) } label: {
                    Label("Редактировать", systemImage: "pencil")
                }
            }
        }
        .accessibilityLabel("Профиль")
    }
}

/// Thin separator between the sections of Обзор (inset like the Android one).
struct OverviewDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal)
    }
}

/// The large rounded tonal tile used for the shortcuts and the social links.
struct OverviewTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .frame(width: 28)
            Text(title).font(.ax(.headline, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// «Комментарии недели»: a bordered card per comment, `<login> [badge] к релизу`
/// over a tappable release title, the text, then the date and a score chip.
/// Tapping the title opens the release, tapping anywhere else opens its comments.
@MainActor
struct OverviewCommentCard: View {
    let comment: ReleaseComment
    var onOpenRelease: (Release) -> Void = { _ in }
    var onOpenComments: (Release) -> Void = { _ in }
    @State private var isSpoilerRevealed = false

    private var release: Release? { comment.release?.value }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(url: comment.authorAvatarURL, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(comment.authorLogin).font(.ax(.headline, .medium)).lineLimit(1)
                    if let badge = comment.profile?.selectedBadge {
                        ProfileBadgeImage(badge: badge, size: 22)
                    }
                    Text("к релизу").font(.ax(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if let release {
                    Button { onOpenRelease(release) } label: {
                        HStack(spacing: 4) {
                            Text(release.displayTitle).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                        }
                        .font(.ax(.subheadline))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                messageBody
                HStack(spacing: 8) {
                    if let date = Format.dateTime(comment.postedAt) {
                        Text(date).font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    if comment.isEdited == true {
                        Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    scoreChip
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { if let release { onOpenComments(release) } }
    }

    @ViewBuilder
    private var messageBody: some View {
        if comment.isDeleted == true {
            Text("Комментарий удалён").font(.ax(.body)).foregroundStyle(.secondary)
        } else if comment.containsSpoiler && !isSpoilerRevealed {
            Button { isSpoilerRevealed = true } label: {
                VStack(spacing: 4) {
                    Text("Комментарий может содержать спойлер.").foregroundStyle(.secondary)
                    Text("Нажмите, чтобы прочитать").font(.ax(.subheadline, .medium))
                }
                .font(.ax(.subheadline))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Text(comment.message ?? "")
                .font(.ax(.body))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scoreColor: Color {
        let votes = comment.voteCount ?? 0
        if votes > 0 { return Color(red: 0.45, green: 0.78, blue: 0.47) }
        if votes < 0 { return Theme.newBadge }
        return .secondary
    }

    private var scoreChip: some View {
        Text(Format.count(comment.voteCount))
            .font(.ax(.subheadline, .medium))
            .monospacedDigit()
            .foregroundStyle(scoreColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(scoreColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// «Обсуждаемое сегодня» row: poster, title, `6 из ? эп • 4.9★`, comment count, kebab.
@MainActor
struct OverviewDiscussionRow: View {
    let release: Release
    let onOverflow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ReleasePoster(url: release.posterURL, width: 84, cornerRadius: 16, aspectRatio: 2.0 / 3.0)
            VStack(alignment: .leading, spacing: 8) {
                Text(release.displayTitle)
                    .font(.ax(.title3, .medium))
                    .lineLimit(2)
                    .padding(.trailing, 28)
                if release.episodeProgressText != nil || release.ratingText != nil {
                    HStack(spacing: 8) {
                        if let episodes = release.episodeProgressText { Text(episodes) }
                        if release.episodeProgressText != nil, release.ratingText != nil { Text("•") }
                        if let rating = release.ratingText {
                            HStack(spacing: 2) { Text(rating).monospacedDigit(); Image(systemName: "star.fill").font(.system(size: 14)) }
                        }
                    }
                    .font(.ax(.body))
                    .foregroundStyle(.secondary)
                }
                if let count = release.commentCount, count > 0 {
                    Label(Plural.comments(count), systemImage: "text.bubble")
                        .font(.ax(.body))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onOverflow) {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Действия с релизом")
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// The beta's section tabs sit in one floating rounded panel instead of a flat
    /// strip with a divider under it.
    func floatingStrip() -> some View {
        padding(.horizontal, 8)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, 8)
    }
}

/// «Коллекции недели»: the collection's cover with its title across the bottom and
/// the comment and bookmark counts as chips in the top corner.
@MainActor
struct OverviewCollectionCard: View {
    let collection: ReleaseCollection

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: collection.coverURL, maxPixelSize: 700) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 300, height: 170)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)

            Text(collection.displayTitle)
                .font(.ax(.title3, .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(16)
        }
        .frame(width: 300, height: 170)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                chip(Format.count(collection.commentCount), systemImage: "text.bubble")
                chip(Format.count(collection.favoriteCount), systemImage: "bookmark")
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Text(text).monospacedDigit()
            Image(systemName: systemImage)
        }
        .font(.ax(.caption, .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }
}
