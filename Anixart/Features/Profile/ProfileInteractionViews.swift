import SwiftUI
import UIKit
import AnixartKit

struct ProfileReportPresentation: Identifiable {
    let id = UUID()
    let kind: ReportTargetKind
    let entityID: Int
    let title: String
    let account: ProfileAccountKey
}

@MainActor
struct ProfileReportView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let target: ProfileReportPresentation
    @State private var reasons = ProfileResource<[ReportReason]>()
    @State private var reasonID: Int?
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSend: Bool {
        env.session.accountKey == target.account && !isSending && !reasons.isLoading
            && reasons.errorMessage == nil && target.entityID > 0
            && reasons.value?.contains(where: { $0.id == reasonID }) == true
            && message.utf16.count <= ReportRequest.messageLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                ProfileAccountNotice(account: target.account)
                if env.session.accountKey == target.account {
                    Section("Объект жалобы") { Text(target.title) }
                    if let values = reasons.value {
                        Section {
                            Picker("Причина жалобы", selection: $reasonID) {
                                Text("Выберите причину").tag(nil as Int?)
                                ForEach(values) { reason in Text(reason.name).tag(Optional(reason.id)) }
                            }
                            TextField("Сообщение", text: $message, axis: .vertical)
                                .lineLimit(4...8)
                                .onChange(of: message) { _, value in
                                    message = ProfileEditorRules.limitedText(value, utf16Limit: ReportRequest.messageLimit)
                                }
                        } footer: { Text("\(message.utf16.count) / \(ReportRequest.messageLimit)") }
                        if values.isEmpty { Text("Причины жалобы недоступны").foregroundStyle(.secondary) }
                    } else {
                        ProfileResourceState(resource: reasons, title: "Не удалось загрузить причины", retry: load)
                    }
                    Section { Link("Правила сообщества", destination: AnixartEnvironment.webBaseURL.appendingPathComponent("rules")) }
                    ProfileSaveError(message: errorMessage ?? reasons.errorMessage)
                }
            }
            .font(.ax(.body))
            .disabled(isSending)
            .navigationTitle("Пожаловаться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(isSending) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отправить") { Task { await send() } }.disabled(!canSend)
                }
            }
        }
        .interactiveDismissDisabled(isSending)
        .task { await load() }
        .onChange(of: env.session.accountKey) { _, current in
            if target.account != current { reasons.reset(); reasonID = nil; message = ""; errorMessage = nil }
        }
    }

    private func load() async {
        await reasons.load { try await env.session.sendAccountRequest(ReportEndpoints.reasons(for: target.kind), for: target.account) }
    }

    private func send() async {
        guard canSend, let reasonID else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await env.session.sendConfirmedAccountRequest(ReportEndpoints.send(to: target.kind, request: .init(
                entityID: target.entityID, reasonID: reasonID, message: message
            )), for: target.account)
            if env.session.accountKey == target.account { dismiss() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { errorMessage = Paginator<Release>.message(for: error) }
        }
    }
}

enum ProfileVoterSource: Hashable, Sendable {
    case article(Int)
    case comment(Int, ProfileCommentCategory)

    func endpoint(page: Int, filter: ProfileVoterFilter) -> Endpoint<PageableResponse<Profile>> {
        switch self {
        case .article(let id): return ArticleEndpoints.voters(id: id, page: page, filter: filter)
        case .comment(let id, let category):
            return ProfileCommentEndpoints.voters(commentID: id, category: category, page: page, filter: filter)
        }
    }
}

@MainActor
struct ProfileVotersView: View {
    @Environment(AppEnvironment.self) private var env
    let source: ProfileVoterSource
    let viewer: ProfileViewerKey
    @State private var filter: ProfileVoterFilter = .all
    @State private var paginator: Paginator<Profile>?

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                HStack {
                    Text(paginator.totalCount.map(Plural.votes) ?? "—").foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Оценки", selection: $filter) {
                            ForEach(ProfileVoterFilter.allCases) { Text($0.title).tag($0) }
                        }
                    } label: { Label(filter.title, systemImage: "line.3.horizontal.decrease") }
                }
                .font(.ax(.subheadline))
                PaginatedContent(paginator: paginator, emptyTitle: "Нет оценок") { profile in
                    NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: {
                        ProfileFriendRow(profile: profile)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Оценили")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: filter) {
            guard viewer == env.session.viewerKey else { return }
            let source = self.source
            let filter = self.filter
            let session = env.session
            let list = Paginator<Profile> { page in
                try await session.sendViewerRequest(source.endpoint(page: page, filter: filter), for: viewer)
            }
            paginator = list
            await list.loadFirstPageIfNeeded()
        }
        .refreshable { await paginator?.reload() }
        .onChange(of: env.session.viewerKey) { _, current in if viewer != current { paginator = nil } }
    }
}

struct ProfileCommentSortHeader: View {
    let totalCount: Int?
    @Binding var sort: ProfileCommentSort
    var body: some View {
        HStack {
            Text(totalCount.map { "\(Format.count($0)) всего" } ?? "—")
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Menu {
                Picker("Сортировка", selection: $sort) {
                    ForEach(ProfileCommentSort.allCases) { Text($0.title).tag($0) }
                }
            } label: { Label(sort.title, systemImage: "arrow.up.arrow.down") }
        }
        .font(.ax(.subheadline))
    }
}

/// Shared by preview links, inline article comments and thread rows. No endpoint
/// is called by opening the menu; reporting still needs a separate explicit send.
@MainActor
struct ProfileCommentContext: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    let comment: ProfileComment
    let category: ProfileCommentCategory?
    let viewer: ProfileViewerKey?
    @State private var showsVoters = false
    @State private var report: ProfileReportPresentation?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if comment.isDeleted != true, let category, let viewer, viewer == env.session.viewerKey {
                    Button { showsVoters = true } label: { Label("Оценили", systemImage: "hand.thumbsup") }
                    Button { UIPasteboard.general.string = comment.message ?? "" } label: { Label("Скопировать", systemImage: "doc.on.doc") }
                    if let account = viewer.account {
                        Button {
                            report = ProfileReportPresentation(kind: .comment(category), entityID: comment.id,
                                                               title: "Комментарий \(comment.profile?.login ?? "пользователя")", account: account)
                        } label: { Label("Пожаловаться", systemImage: "flag") }
                    }
                }
            }
            .fullScreenCover(isPresented: $showsVoters) {
                if let category, let viewer {
                    NavigationStack {
                        ProfileVotersView(source: .comment(comment.id, category), viewer: viewer)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { showsVoters = false } } }
                    }
                }
            }
            .sheet(item: $report) { ProfileReportView(target: $0) }
            .onChange(of: env.session.viewerKey) { _, current in
                if viewer != current { showsVoters = false; report = nil }
            }
    }
}

extension View {
    @MainActor
    func profileCommentContext(_ comment: ProfileComment, category: ProfileCommentCategory?, viewer: ProfileViewerKey?) -> some View {
        modifier(ProfileCommentContext(comment: comment, category: category, viewer: viewer))
    }
}

@MainActor
struct ProfileReputationHelpView: View {
    let score: Int
    var body: some View {
        ProfileHelpSheet(title: "Уровень репутации", paragraphs: [
            "Ваш уровень репутации: \(score). Он отображается рядом с никнеймом на странице профиля.",
            "Повышайте репутацию, оставляя полезные комментарии, создавая интересные коллекции и заводя новых друзей.",
            "В случае токсичного поведения уровень репутации падает. Чем ниже уровень, тем больше ограничений на социальную активность."
        ])
    }
}
