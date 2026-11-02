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
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { dismiss() }
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 20) {
                            if let image = ProfileMascotArtwork.image {
                                Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                                    .frame(height: min(220, geometry.size.height * 0.27)).accessibilityHidden(true)
                            }
                            VStack(spacing: 8) {
                                HStack {
                                    Text("\(score) уровень").font(.ax(.subheadline, .medium))
                                    Spacer()
                                    Text("\(minimum) уровень").font(.ax(.subheadline, .medium))
                                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(LinearGradient(colors: [Color(red: 0.94, green: 0.31, blue: 0.36), .orange],
                                                                   startPoint: .leading, endPoint: .trailing), in: Capsule())
                                }
                                ProgressView(value: ProfileBlogEntryPolicy.progress(score: score, minimum: minimum))
                                    .tint(Theme.selection)
                                Text("Для улучшения профиля необходим \(minimum)-й уровень репутации.")
                                    .font(.ax(.subheadline)).multilineTextAlignment(.center)
                                Button("Узнай как повысить »") { showsHelp = true }
                                    .font(.ax(.subheadline, .medium)).underline()
                            }
                            feature("Публикация записей в профиле", detail: "Друзья будут видеть твои публикации в своей ленте", symbol: "pencil")
                            feature("Создание каналов по интересам", detail: "Собери свой фандом по Наруто или просто публикуй котиков", symbol: "sparkles")
                            feature("Установка обложки профиля", detail: "Выделись с помощью стильной обложки", symbol: "photo.on.rectangle")
                        }.padding(24)
                    }
                    .frame(maxHeight: max(240, geometry.size.height * 0.78 - 64))
                    Button { dismiss() } label: {
                        Text("Понятно").font(.ax(.headline)).frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(Capsule().strokeBorder(Theme.selection.opacity(0.25), lineWidth: 1))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 20)
                }
                .frame(width: min(380, max(240, geometry.size.width - 40)))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 28))
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

    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.ax(.title3)).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.ax(.subheadline, .medium))
                Text(detail).font(.ax(.subheadline)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}
