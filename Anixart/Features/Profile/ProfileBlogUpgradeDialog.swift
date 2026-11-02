import SwiftUI
import UIKit
import AnixartKit

enum ProfileBlogEntryPolicy {
    static func requiresUpgrade(profile: Profile, channel: Channel?, minimum: Int) -> Bool {
        channel == nil && (profile.ratingScore ?? 0) < max(0, minimum)
    }
    static func progress(score: Int, minimum: Int) -> Double {
        guard minimum > 0 else { return 1 }
        return min(1, max(0, Double(score) / Double(minimum)))
    }
}

struct ProfileBlogUpgradeLayout: Equatable {
    let size: CGSize
    let artworkHeight: CGFloat

    /// GeometryReader's proposal excludes safe areas. Reserve a small outside
    /// margin and give the explanation the height previously lost to the 78% cap.
    init(available: CGSize) {
        let width = available.width.isFinite ? max(0, available.width - 24) : 0
        let height = available.height.isFinite ? max(0, available.height - 24) : 0
        size = CGSize(width: min(420, width), height: min(840, height))
        artworkHeight = min(180, size.height * 0.2)
    }
}

enum ProfileBlogUpgradeFeature: String, CaseIterable, Hashable, Identifiable {
    case posts, channels, cover
    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: return "Публикация записей в профиле"
        case .channels: return "Создание каналов по интересам"
        case .cover: return "Установка обложки профиля"
        }
    }

    var detail: String {
        switch self {
        case .posts: return "Друзья будут видеть твои публикации в своей ленте"
        case .channels: return "Собери свой фандом по Наруто или просто публикуй котиков"
        case .cover: return "Выделись с помощью стильной обложки"
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "pencil"
        case .channels: return "sparkles"
        case .cover: return "photo.on.rectangle"
        }
    }
}

/// Local original Anixa artwork used by Android's dialog_blog_create. No
/// brightness/tint treatment and no remote download or blog mutation on opening.
@MainActor
enum ProfileMascotArtwork {
    static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "anixa_wow", withExtension: "webp"),
              let data = try? Data(contentsOf: url), let source = PhotoImageDecoder.source(from: data) else { return nil }
        return PhotoImageDecoder.thumbnail(from: source, pixelSize: 720)
    }()
}

@MainActor
struct ProfileBlogUpgradeDialog: View {
    @Environment(\.dismiss) private var dismiss
    let score: Int
    let minimum: Int
    @State private var showsHelp = false

    var body: some View {
        GeometryReader { geometry in
            let layout = ProfileBlogUpgradeLayout(available: geometry.size)
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { dismiss() }.accessibilityHidden(true)
                VStack(spacing: 0) {
                    ScrollView {
                        ProfileBlogUpgradeContent(score: score, minimum: minimum, artworkHeight: layout.artworkHeight) {
                            showsHelp = true
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.visible)
                    ProfileBlogUpgradeCloseButton { dismiss() }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                .accessibilityIdentifier("profile.blogUpgrade")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .presentationBackground(.clear)
        .sheet(isPresented: $showsHelp) {
            ProfileHelpSheet(title: "Как повысить репутацию", paragraphs: [
                "У каждого пользователя существует свой уровень репутации. Он может повышаться и понижаться в зависимости от действий.",
                "Чтобы повысить репутацию, оставляй полезные комментарии к релизам, создавай интересные коллекции и заводи новых друзей. При токсичном поведении уровень может понижаться.",
                "После достижения \(minimum)-го уровня можно улучшить профиль. Полученные возможности остаются даже при последующем снижении репутации."
            ])
        }
    }
}

@MainActor
struct ProfileBlogUpgradeCloseButton: View {
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Text("Понятно").font(.ax(.headline)).frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(Theme.selection.opacity(0.25), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 16)
        .accessibilityIdentifier("profile.blogUpgrade.close")
    }
}

@MainActor
struct ProfileBlogUpgradeContent: View {
    static let publishingLimitation = "В iOS создание записей и каналов пока не поддерживается."
    let score: Int
    let minimum: Int
    let artworkHeight: CGFloat
    let onHelp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let image = ProfileMascotArtwork.image {
                Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                    .frame(height: artworkHeight).accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("\(score) уровень").font(.ax(.subheadline, .medium))
                    Spacer(minLength: 12)
                    Text("\(minimum) уровень").font(.ax(.subheadline, .medium))
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(LinearGradient(colors: [Color(red: 0.94, green: 0.31, blue: 0.36), .orange],
                                                   startPoint: .leading, endPoint: .trailing), in: Capsule())
                }
                ProgressView(value: ProfileBlogEntryPolicy.progress(score: score, minimum: minimum))
                    .tint(Theme.selection)
                Text("Для улучшения профиля необходим \(minimum)-й уровень репутации.")
                    .font(.ax(.subheadline)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Узнай как повысить »", action: onHelp)
                    .font(.ax(.subheadline, .medium)).underline()
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("profile.blogUpgrade.help")
            }
            ForEach(ProfileBlogUpgradeFeature.allCases) { feature in
                featureRow(feature)
            }
            Text(Self.publishingLimitation)
                .font(.ax(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private func featureRow(_ feature: ProfileBlogUpgradeFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.systemImage).font(.ax(.title3)).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title).font(.ax(.subheadline, .medium))
                Text(feature.detail).font(.ax(.subheadline)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.blogUpgrade.feature.\(feature.id)")
    }
}
