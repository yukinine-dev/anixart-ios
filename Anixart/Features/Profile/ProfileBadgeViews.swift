import SwiftUI
import AnixartKit

@MainActor
@Observable
final class ProfileBadgesModel {
    let resource = ProfileResource<ProfileBadgeSectionsResponse>()
    private(set) var isSaving = false
    var errorMessage: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var response: ProfileBadgeSectionsResponse? { resource.value }
    var showcased: [Badge] { response?.showcased ?? [] }
    var selectedID: Int? { response?.profile?.badge?.id ?? response?.profile?.badgeId }

    func badge(id: Int, fallback: Badge) -> Badge {
        let all = showcased + (response?.recent ?? []) + (response?.sections ?? []).flatMap { $0.content ?? [] }
        return all.first { $0.id == id } ?? fallback
    }

    func load(profileID: Int, session: SessionController, viewer: ProfileViewerKey) async {
        let recent = ProfileRecentBadges.query(profileID: profileID, defaults: defaults)
        await resource.load {
            try await session.sendViewerRequest(ProfileBadgeEndpoints.sections(profileID: profileID, recent: recent), for: viewer)
        }
    }

    enum Action { case select, remove, pin, unpin }

    @discardableResult
    func apply(_ action: Action, to badge: Badge, account: ProfileAccountKey,
               session: SessionController) async -> Bool {
        guard !isSaving, session.accountKey == account else { return false }
        if action == .pin, !showcased.contains(where: { $0.id == badge.id }),
           showcased.count >= ProfileEditorRules.showcaseLimit {
            errorMessage = "Можно закрепить не более трёх значков. Сначала открепите один из них."
            return false
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            switch action {
            case .select:
                try await session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.select(id: badge.id), for: account)
                ProfileRecentBadges.record(badge.id, profileID: account.profileID, defaults: defaults)
            case .remove:
                try await session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.remove(), for: account)
            case .pin:
                try await session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.pin(id: badge.id), for: account)
            case .unpin:
                try await session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.unpin(id: badge.id), for: account)
            }
            await load(profileID: account.profileID, session: session, viewer: account.viewerKey)
            await session.refreshProfile(for: account)
            return session.accountKey == account && !Task.isCancelled
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
            return false
        }
    }
}

@MainActor
enum ProfileRecentBadges {
    private static func key(_ profileID: Int) -> String { "profile.\(profileID).recentBadgeIDs" }

    static func record(_ id: Int, profileID: Int, defaults: UserDefaults = .standard) {
        let old = defaults.array(forKey: key(profileID)) as? [Int] ?? []
        defaults.set(ProfileEditorRules.recentBadgeIDs(adding: id, to: old), forKey: key(profileID))
    }

    static func query(profileID: Int, defaults: UserDefaults = .standard) -> String? {
        let ids = Array((defaults.array(forKey: key(profileID)) as? [Int] ?? [])
            .prefix(ProfileEditorRules.recentBadgeLimit))
        guard !ids.isEmpty, let data = try? JSONEncoder().encode(ids) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
struct ProfileBadgesView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    var selecting = false
    @State private var model = ProfileBadgesModel()
    @State private var viewer: ProfileViewerKey?
    @State private var detail: Badge?
    @State private var claimsBadge = false
    @State private var confirmsRemove = false
    @State private var showsHelp = false

    init(profileID: Int, selecting: Bool = false, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        self.selecting = selecting
        _viewer = State(initialValue: viewer)
    }

    private var account: ProfileAccountKey? { viewer?.account }
    private var ownsProfile: Bool { viewer == env.session.viewerKey && account?.profileID == profileID }

    var body: some View {
        ScrollView {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let response = model.response {
                VStack(alignment: .leading, spacing: 28) {
                    if selecting, ownsProfile, let profile = response.profile ?? env.session.profile {
                        ProfileBadgeCommentPreview(profile: profile)
                    }
                    if let recent = response.recent, !recent.isEmpty {
                        badgeSection("Недавние", badges: Array(recent.prefix(ProfileEditorRules.recentBadgeLimit)))
                    }
                    if !model.showcased.isEmpty {
                        badgeSection("Закреплённые", badges: model.showcased)
                    }
                    ForEach(response.sections ?? []) { section in
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(section.title ?? "Значки").font(.ax(.headline))
                                Text(Format.count(section.count)).font(.ax(.caption)).foregroundStyle(.secondary)
                                    .padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                                Spacer()
                                if (section.count ?? 0) > (section.content?.count ?? 0) {
                                    NavigationLink("Показать все") {
                                        ProfileBadgeCategoryView(profileID: profileID, section: section, selecting: selecting,
                                                                 model: model, viewer: viewer)
                                    }
                                    .font(.ax(.subheadline))
                                }
                            }
                            LazyVGrid(columns: ProfileBadgeGridLayout.columns, alignment: .leading, spacing: 20) {
                                ForEach(Array((section.content ?? []).prefix(ProfileEditorRules.categoryBadgePreviewLimit))) { badge in
                                    Button { detail = badge } label: {
                                        ProfileBadgeTile(badge: badge, selected: selecting && model.selectedID == badge.id, compact: true)
                                    }.buttonStyle(.plain)
                                }
                                let shown = min(section.content?.count ?? 0, ProfileEditorRules.categoryBadgePreviewLimit)
                                if (section.count ?? shown) > shown {
                                    NavigationLink {
                                        ProfileBadgeCategoryView(profileID: profileID, section: section, selecting: selecting, model: model, viewer: viewer)
                                    } label: { ProfileBadgeMoreTile(remaining: (section.count ?? shown) - shown) }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if (response.sections ?? []).allSatisfy({ ($0.content ?? []).isEmpty }) && model.showcased.isEmpty {
                        ProfileEmptySection(message: "Значков пока нет")
                    }
                    ProfileSaveError(message: model.resource.errorMessage)
                }
                .padding()
            } else if viewer == nil || viewer == env.session.viewerKey {
                ProfileResourceState(resource: model.resource, title: "Не удалось загрузить значки", retry: reload)
            }
        }
        .navigationTitle(selecting ? "Установка значка" : "Значки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if ownsProfile {
                    Menu {
                        Button { claimsBadge = true } label: { Label("Получить по коду", systemImage: "gift") }
                        Button { showsHelp = true } label: { Label("О значках", systemImage: "info.circle") }
                        if model.selectedID != nil || env.session.profile?.badge != nil {
                            Button(role: .destructive) { confirmsRemove = true } label: { Label("Снять значок", systemImage: "minus.circle") }
                        }
                        NavigationLink { ProfileBadgeOrderView(profileID: profileID, account: account) } label: {
                            Label("Изменить порядок", systemImage: "arrow.up.arrow.down")
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .disabled(model.isSaving)
                }
            }
        }
        .task(id: env.session.profileRevision) {
            if viewer == nil { viewer = env.session.viewerKey }
            if !model.isSaving { await reload() }
        }
        .onChange(of: env.session.viewerKey) { _, current in
            guard viewer != current else { return }
            model.resource.reset()
            model.errorMessage = nil
            detail = nil
            claimsBadge = false
            confirmsRemove = false
        }
        .refreshable { await reload() }
        .sheet(item: $detail) { badge in
            ProfileBadgeDetailSheet(badge: badge, profileID: profileID, model: model,
                                    selecting: selecting, viewer: viewer)
        }
        .sheet(isPresented: $claimsBadge) {
            ProfileBadgeClaimView(account: account) { await reload() }
        }
        .sheet(isPresented: $showsHelp) {
            ProfileHelpSheet(title: "О значках", paragraphs: [
                "Значки можно получать за просмотр аниме, участие в событиях и конкурсах, а также по коду или ссылке.",
                "Установленный значок отображается рядом с никнеймом. Закрепление на витрине — отдельное действие; на ней можно разместить до трёх значков."
            ])
        }
        .confirmationDialog("Снять значок?", isPresented: $confirmsRemove, titleVisibility: .visible) {
            Button("Снять", role: .destructive) { Task { await removeSelected() } }
        } message: { Text("Значок останется в вашей коллекции, но не будет отображаться рядом с никнеймом.") }
        .alert("Значки", isPresented: Binding(get: { model.errorMessage != nil && detail == nil },
                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func badgeSection(_ title: String, badges: [Badge]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.ax(.headline))
            badgeGrid(badges)
        }
    }

    private func badgeGrid(_ badges: [Badge]) -> some View {
        LazyVGrid(columns: ProfileBadgeGridLayout.columns, alignment: .leading, spacing: 20) {
            ForEach(badges) { badge in
                Button { detail = badge } label: {
                    ProfileBadgeTile(badge: badge, selected: selecting && (model.selectedID == badge.id || badge.isSelected == true), compact: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reload() async {
        guard let viewer, viewer == env.session.viewerKey else { return }
        await model.load(profileID: profileID, session: env.session, viewer: viewer)
    }

    private func removeSelected() async {
        guard ownsProfile, let account,
              let badge = model.response?.profile?.badge ?? env.session.profile?.badge else { return }
        await model.apply(.remove, to: badge, account: account, session: env.session)
    }
}

@MainActor
struct ProfileBadgeCategoryView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    let section: BadgeSection
    let selecting: Bool
    let model: ProfileBadgesModel
    let viewer: ProfileViewerKey?
    @State private var paginator: Paginator<Badge>?
    @State private var detail: Badge?

    var body: some View {
        ScrollView {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                if paginator.isLoadingFirstPage { ProgressView().padding(40) }
                else if let error = paginator.errorMessage, paginator.items.isEmpty {
                    StatusMessageView(title: "Не удалось загрузить значки", message: error, retry: { await paginator.retry() })
                } else if paginator.isEmpty { ProfileEmptySection(message: "Значков пока нет") }
                else {
                    LazyVGrid(columns: ProfileBadgeGridLayout.columns, spacing: 20) {
                        ForEach(paginator.items) { badge in
                            Button { detail = badge } label: {
                                ProfileBadgeTile(badge: badge, selected: selecting && model.selectedID == badge.id, compact: true)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if badge.id == paginator.items.last?.id { Task { await paginator.loadNextPage() } }
                            }
                        }
                    }
                    .padding()
                    if paginator.state == .loading { ProgressView().padding() }
                    if let error = paginator.errorMessage {
                        StatusMessageView(title: "Не удалось загрузить следующую страницу", message: error, retry: { await paginator.retry() })
                    }
                }
            }
        }
        .navigationTitle(section.title ?? "Значки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard let viewer, viewer == env.session.viewerKey else { return }
            if paginator == nil {
                let session = env.session
                let id = profileID
                let category = section.id
                paginator = Paginator { page in try await session.sendViewerRequest(ProfileBadgeEndpoints.all(profileID: id, categoryID: category, page: page), for: viewer) }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .refreshable { await paginator?.reload() }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { paginator = nil; detail = nil }
        }
        .sheet(item: $detail) { badge in
            ProfileBadgeDetailSheet(badge: badge, profileID: profileID, model: model, selecting: selecting, viewer: viewer)
        }
    }
}

@MainActor
struct ProfileBadgeDetailSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let badge: Badge
    let profileID: Int
    let model: ProfileBadgesModel
    var selecting = false
    let viewer: ProfileViewerKey?
    @State private var showsAward = false

    private var current: Badge { model.badge(id: badge.id, fallback: badge) }
    private var account: ProfileAccountKey? { viewer?.account }
    private var ownsProfile: Bool { viewer == env.session.viewerKey && account?.profileID == profileID }
    private var isSelected: Bool { model.selectedID == badge.id || current.isSelected == true }
    private var isPinned: Bool { model.showcased.contains { $0.id == badge.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProfileViewerNotice(viewer: viewer)
                    if viewer == env.session.viewerKey {
                    ProfileBadgeImage(badge: current, size: 136)
                        .padding(16)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.quaternary))
                    Text(ProfileBadgeStyle.rarityTitle(current.rarity)).font(.ax(.caption, .medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    Text(current.name ?? "Значок").font(.ax(.title, .bold)).multilineTextAlignment(.center)
                    if let description = current.description, !description.isEmpty {
                        Text(description).font(.ax(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let percentage = current.ownershipPercentage {
                        Text("Есть у \(percentage.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU"))))% пользователей")
                            .font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    if let timestamp = current.timestamp, timestamp > 0 {
                        Text("Получен \(ProfileDate.text(timestamp))").font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    if let award = current.award {
                        if showsAward { ProfileBadgeAwardView(award: award, viewer: viewer) }
                        else { Button("Как был получен") { showsAward = true }.padding(.vertical, 10) }
                    }
                    if ownsProfile, current.isOwned == true {
                        Button {
                            Task { await apply(isSelected ? .remove : .select) }
                        } label: {
                            Text(isSelected ? "Снять" : "Установить")
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSaving)
                    }
                    if let error = model.errorMessage ?? model.resource.errorMessage {
                        Text(error).font(.ax(.subheadline)).foregroundStyle(.red)
                    }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Значок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if ownsProfile, current.isOwned == true {
                        Button { Task { await apply(isPinned ? .unpin : .pin) } } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                        }
                        .disabled(model.isSaving)
                        .accessibilityLabel(isPinned ? "Открепить от витрины" : "Закрепить на витрине")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.isSaving)
        .onAppear { model.errorMessage = nil }
    }

    private func apply(_ action: ProfileBadgesModel.Action) async {
        guard let account else { return }
        if await model.apply(action, to: current, account: account, session: env.session),
           selecting, action == .select || action == .remove { dismiss() }
    }
}

@MainActor
struct ProfileBadgeAwardView: View {
    let award: BadgeAward
    let viewer: ProfileViewerKey?
    var body: some View {
        if let id = award.releaseId {
            NavigationLink { ReleaseDetailView(releaseID: id, viewer: viewer) } label: {
                HStack(spacing: 14) {
                    ReleasePoster(url: AnixartURL.image(award.releaseImage), width: 54)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(award.releaseTitle ?? "Открыть релиз").font(.ax(.headline)).foregroundStyle(.primary)
                        if let status = award.profileListStatus.flatMap(ProfileListStatus.init(rawValue:)) {
                            Text("В списке «\(status.title)»").font(.ax(.subheadline)).foregroundStyle(.secondary)
                        } else if let episode = award.episodeName {
                            Text(episode).font(.ax(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(14).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Text("Получен по коду или ссылке").font(.ax(.subheadline)).foregroundStyle(.secondary)
        }
    }
}

struct ProfileBadgeImage: View {
    let badge: Badge
    var size: CGFloat = 88
    var body: some View {
        CachedAsyncImage(url: AnixartURL.image(badge.imageMediumUrl ?? badge.badgeUrl ?? badge.imageSmallUrl), maxPixelSize: size) {
            $0.resizable().scaledToFit()
        } placeholder: { Image(systemName: "seal").resizable().scaledToFit().foregroundStyle(.tertiary).padding(12) }
        .frame(width: size, height: size)
    }
}

struct ProfileBadgeTile: View {
    let badge: Badge
    var selected = false
    var compact = false
    var body: some View {
        VStack(spacing: 10) {
            ProfileBadgeImage(badge: badge, size: compact ? 44 : 76).padding(compact ? 8 : 12)
                .background(Color.primary.opacity(selected ? 0.12 : 0.035), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Theme.accent : ProfileBadgeStyle.color(badge.rarity).opacity(0.6), lineWidth: selected ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).padding(8) }
                }
            Text(badge.name ?? "Значок").font(.ax(compact ? .caption : .subheadline, .medium)).lineLimit(2).multilineTextAlignment(.center)
            if !compact, let title = badge.award?.releaseTitle {
                Text(title).font(.ax(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .opacity(badge.isOwned == false ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

enum ProfileBadgeGridLayout {
    static var columns: [GridItem] { Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: 4) }
}

struct ProfileBadgeMoreTile: View {
    let remaining: Int?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.right").font(.ax(.title2)).frame(width: 60, height: 60)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(remaining.map { "Ещё \(Format.count($0))" } ?? "Все значки")
                .font(.ax(.caption, .medium)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

@MainActor
struct ProfileBadgePreviewGrid: View {
    @Environment(AppEnvironment.self) private var env
    let badges: [Badge]
    let totalCount: Int?
    let profileID: Int
    let viewer: ProfileViewerKey?
    @State private var detail: Badge?
    @State private var model = ProfileBadgesModel()

    private var preview: [Badge] { Array(badges.prefix(ProfileEditorRules.badgePreviewLimit)) }
    private var remaining: Int? { totalCount.map { max(0, $0 - preview.count) } }

    var body: some View {
        LazyVGrid(columns: ProfileBadgeGridLayout.columns, alignment: .leading, spacing: 20) {
            ForEach(preview) { badge in
                Button { if viewer == env.session.viewerKey { detail = badge } } label: {
                    ProfileBadgeTile(badge: badge, compact: true)
                }
                .buttonStyle(.plain)
            }
            if remaining == nil || (remaining ?? 0) > 0 || badges.count > preview.count {
                NavigationLink { ProfileBadgesView(profileID: profileID, viewer: viewer) } label: {
                    ProfileBadgeMoreTile(remaining: remaining ?? (badges.count > preview.count ? badges.count - preview.count : nil))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .sheet(item: $detail) { badge in
            ProfileBadgeDetailSheet(badge: badge, profileID: profileID, model: model, viewer: viewer)
                .task { if let viewer { await model.load(profileID: profileID, session: env.session, viewer: viewer) } }
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { detail = nil; model.resource.reset() }
        }
    }
}

enum ProfileBadgeStyle {
    static func rarityTitle(_ value: String?) -> String {
        switch value?.uppercased() {
        case "COMMON": return "Обычный"
        case "UNCOMMON": return "Необычный"
        case "RARE": return "Редкий"
        case "EPIC": return "Эпический"
        case "LEGENDARY": return "Легендарный"
        default: return value ?? "Значок"
        }
    }

    static func color(_ value: String?) -> Color {
        switch value?.uppercased() {
        case "UNCOMMON": return .green
        case "RARE": return .blue
        case "EPIC": return Theme.accent
        case "LEGENDARY": return Theme.sponsorGold
        default: return .secondary
        }
    }
}

struct ProfileBadgeCommentPreview: View {
    let profile: Profile
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(url: profile.avatarURL, size: 48)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text(profile.displayLogin).font(.ax(.subheadline, .semibold))
                    if let badge = profile.badge { ProfileBadgeImage(badge: badge, size: 20) }
                    Text("сегодня").font(.ax(.caption)).foregroundStyle(.secondary)
                }
                Text("Это пример вашего комментария").font(.ax(.subheadline))
            }
            Spacer(minLength: 0)
        }
        .padding(16).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}

@MainActor
struct ProfileBadgeStrip: View {
    let badges: [Badge]
    let profileID: Int
    let viewer: ProfileViewerKey?
    @State private var detail: Presentation?
    @State private var model = ProfileBadgesModel()
    @Environment(AppEnvironment.self) private var env

    private struct Presentation: Identifiable {
        let badge: Badge
        let viewer: ProfileViewerKey
        var id: Int { badge.id }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(badges) { badge in
                    Button {
                        guard let viewer, viewer == env.session.viewerKey else { return }
                        detail = Presentation(badge: badge, viewer: viewer)
                    } label: { ProfileBadgeTile(badge: badge).frame(width: 110) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .sheet(item: $detail) { item in
            ProfileBadgeDetailSheet(badge: item.badge, profileID: profileID, model: model, viewer: item.viewer)
                .task { await model.load(profileID: profileID, session: env.session, viewer: item.viewer) }
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { detail = nil; model.resource.reset() }
        }
    }
}

@MainActor
struct ProfileBadgeClaimView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    var onClaim: () async -> Void
    @State private var input = ""
    @State private var preview = ProfileResource<BadgeClaimPreviewResponse>()
    @State private var previewCode: String?
    @State private var account: ProfileAccountKey?
    @State private var isClaiming = false
    @State private var hasClaimed = false
    @State private var errorMessage: String?

    init(account: ProfileAccountKey?, onClaim: @escaping () async -> Void) {
        _account = State(initialValue: account)
        self.onClaim = onClaim
    }

    var body: some View {
        NavigationStack {
            Form {
                ProfileAccountNotice(account: account)
                if account != nil, env.session.accountKey == account {
                if hasClaimed {
                    Section { Label("Значок получен", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.accent) }
                } else {
                    Section("Код значка") {
                        TextField("Код или ссылка", text: $input).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button("Проверить") { Task { await check() } }
                            .disabled(preview.isLoading || env.session.accountKey != account || BadgeClaimCode.normalized(input) == nil)
                    }
                    if let achievement = preview.value?.achievement, previewCode == BadgeClaimCode.normalized(input), let badge = achievement.badge {
                        Section {
                            VStack(spacing: 12) {
                                ProfileBadgeImage(badge: badge, size: 120)
                                Text(badge.name ?? achievement.name ?? "Значок").font(.ax(.headline))
                                if let description = badge.description { Text(description).font(.ax(.subheadline)).foregroundStyle(.secondary) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            Button("Получить значок") { Task { await claim(badge) } }
                                .disabled(isClaiming || env.session.accountKey != account)
                        }
                    }
                    if preview.isLoading { ProgressView().frame(maxWidth: .infinity) }
                    ProfileSaveError(message: errorMessage ?? preview.errorMessage)
                }
                }
            }
            .disabled(isClaiming || account == nil || env.session.accountKey != account)
            .navigationTitle("Получение значка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(hasClaimed ? "Готово" : "Закрыть") { dismiss() }.disabled(isClaiming) } }
        }
        .interactiveDismissDisabled(isClaiming)
        .onChange(of: env.session.accountKey) { _, current in
            guard account != current else { return }
            input = ""
            previewCode = nil
            preview.reset()
            hasClaimed = false
            errorMessage = nil
        }
    }

    private func check() async {
        guard !preview.isLoading, !isClaiming, let account, env.session.accountKey == account,
              let code = BadgeClaimCode.normalized(input) else { return }
        errorMessage = nil
        previewCode = nil
        let response = await preview.load { try await env.session.sendViewerRequest(ProfileBadgeEndpoints.preview(code: code), for: account.viewerKey) }
        guard env.session.accountKey == account, code == BadgeClaimCode.normalized(input), !Task.isCancelled else { return }
        if response?.achievement?.badge != nil { previewCode = code }
        else { previewCode = nil }
    }

    private func claim(_ badge: Badge) async {
        guard !isClaiming, let account, let code = previewCode, code == BadgeClaimCode.normalized(input) else { return }
        isClaiming = true
        defer { isClaiming = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.claim(code: code, badgeID: badge.id), for: account)
            hasClaimed = true
            await env.session.refreshProfile(for: account)
            if env.session.accountKey == account { await onClaim() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}
