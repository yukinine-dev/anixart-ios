import SwiftUI
import AnixartKit

@MainActor
struct ProfileCommentsView: View {
    @Environment(AppEnvironment.self) private var env
    let profileID: Int
    @State private var viewer: ProfileViewerKey?
    @State private var category: ProfileCommentCategory = .releases
    @State private var lists: [ProfileCommentCategory: Paginator<ProfileComment>] = [:]
    @State private var sorts: [ProfileCommentCategory: ProfileCommentSort] = [:]
    @State private var loadedSorts: [ProfileCommentCategory: ProfileCommentSort] = [:]

    private var paginator: Paginator<ProfileComment>? { lists[category] }
    private var sort: ProfileCommentSort {
        get { sorts[category] ?? .newest }
        nonmutating set { sorts[category] = newValue }
    }

    init(profileID: Int, viewer: ProfileViewerKey? = nil) {
        self.profileID = profileID
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        List {
            ProfileViewerNotice(viewer: viewer)
            if viewer == env.session.viewerKey, let paginator {
                ProfileCommentSortHeader(totalCount: paginator.totalCount,
                                         sort: Binding(get: { sort }, set: { sort = $0 }))
                PaginatedContent(paginator: paginator, emptyTitle: "Комментариев пока нет") { comment in
                    ProfileCommentLink(comment: comment, fallbackCategory: category, viewer: viewer)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ProfileCommentCategory.allCases) { candidate in
                        Button { category = candidate } label: {
                            Text(candidate.title + (lists[candidate]?.totalCount.flatMap { $0 > 0 ? " · \(Format.count($0))" : nil } ?? ""))
                                .font(.ax(.subheadline))
                                .padding(10)
                                .background(category == candidate ? Theme.accent.opacity(0.15) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == candidate ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8).background(.bar)
        }
        .refreshable { await paginator?.reload() }
        .task(id: "\(category.rawValue)-\(sort.rawValue)") {
            if viewer == nil { viewer = env.session.viewerKey }
            guard let viewer, viewer == env.session.viewerKey else { return }
            let session = env.session
            let id = profileID
            let category = self.category
            let sort = self.sort
            if loadedSorts[category] != sort || lists[category] == nil {
                lists[category] = Paginator<ProfileComment> { page in
                    try await session.sendViewerRequest(ProfileEndpoints.comments(profileID: id, category: category, page: page, sort: sort.rawValue), for: viewer)
                }
                loadedSorts[category] = sort
            }
            await lists[category]?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { lists = [:]; sorts = [:]; loadedSorts = [:] }
        }
    }
}

@MainActor
struct ProfileCommentLink: View {
    let comment: ProfileComment
    var fallbackCategory: ProfileCommentCategory?
    var fallbackLocation: ProfileCommentLocation?
    var viewer: ProfileViewerKey?

    var body: some View {
        if let category = comment.category ?? fallbackLocation?.category ?? fallbackCategory {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    ProfileCommentDetailView(commentID: comment.id, category: category, preloaded: comment,
                                             fallbackLocation: fallbackLocation, viewer: viewer)
                } label: {
                    ProfileCommentPreviewCard(comment: comment)
                }
                .buttonStyle(.plain)
                if let count = comment.replyCount, count > 0 {
                    NavigationLink("Показать \(Plural.replies(count))") {
                        ProfileCommentDetailView(commentID: comment.threadRootID, category: category,
                                                 preloaded: comment.threadRootID == comment.id ? comment : nil,
                                                 fallbackLocation: fallbackLocation ?? comment.location, viewer: viewer)
                    }
                    .font(.ax(.subheadline)).padding(.leading, 52).padding(.bottom, 10)
                }
            }
            .profileCommentContext(comment, category: category, viewer: viewer)
        } else {
            ProfileCommentPreviewCard(comment: comment)
        }
    }
}

struct ProfileCommentPreviewCard: View {
    let comment: ProfileComment
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: AnixartURL.image(comment.profile?.avatar), size: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(comment.profile?.login ?? "Пользователь").font(.ax(.subheadline, .medium)).foregroundStyle(.primary)
                    if let date = Format.relativeDate(comment.date) {
                        Text(date).font(.ax(.caption)).foregroundStyle(.secondary)
                    }
                }
                Text(ProfileCommentPresentation.parentTitle(comment)).font(.ax(.caption)).foregroundStyle(Theme.accent).lineLimit(2)
                if comment.isDeleted == true {
                    Text("Комментарий удалён").foregroundStyle(.secondary)
                } else if comment.isSpoiler == true {
                    Label("Содержит спойлер", systemImage: "eye.slash").foregroundStyle(.secondary)
                } else {
                    Text(comment.message ?? "").foregroundStyle(.primary).lineLimit(5)
                }
                HStack(spacing: 14) {
                    Label(Format.count(comment.voteCount), systemImage: "hand.thumbsup")
                    Label(Format.count(comment.replyCount), systemImage: "bubble.left")
                }
                .font(.ax(.caption)).foregroundStyle(.secondary)
            }
            .font(.ax(.subheadline))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

enum ProfileCommentPresentation {
    static func parentTitle(_ comment: ProfileComment) -> String {
        if let release = comment.release { return release.value?.displayTitle ?? "Комментарий к релизу" }
        if let collection = comment.collection { return collection.value?.displayTitle ?? "Комментарий к коллекции" }
        if let article = comment.article { return article.value?.channel?.title ?? "Комментарий к записи" }
        return "Комментарий"
    }
}

@MainActor
struct ProfileCommentDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let commentID: Int
    let category: ProfileCommentCategory
    var preloaded: ProfileComment?
    var fallbackLocation: ProfileCommentLocation?
    @State private var resource = ProfileResource<ProfileComment>()
    @State private var parent = ProfileResource<ProfileComment>()
    @State private var replies: Paginator<ProfileComment>?
    @State private var repliesRootID: Int?
    @State private var sort: ProfileCommentSort = .oldest
    @State private var loadedRepliesSort: ProfileCommentSort?
    @State private var loadGeneration = 0
    @State private var composer: ProfileCommentDraft
    @State private var votingIDs = Set<Int>()
    @State private var actionError: String?

    init(commentID: Int, category: ProfileCommentCategory, preloaded: ProfileComment? = nil,
         fallbackLocation: ProfileCommentLocation? = nil, viewer: ProfileViewerKey? = nil) {
        self.commentID = commentID
        self.category = category
        self.preloaded = preloaded?.id == commentID && (preloaded?.category == nil || preloaded?.category == category) ? preloaded : nil
        self.fallbackLocation = fallbackLocation?.category == category && (fallbackLocation?.parentID ?? 0) > 0 ? fallbackLocation : nil
        _composer = State(initialValue: ProfileCommentDraft(viewer: viewer))
    }

    private var comment: ProfileComment? { resource.value ?? preloaded }
    private var location: ProfileCommentLocation? { comment?.location ?? parent.value?.location ?? fallbackLocation }
    private var rootID: Int { comment?.threadRootID ?? commentID }
    private var hasCurrentViewer: Bool { composer.viewer == env.session.viewerKey }
    private var actionsEnabled: Bool { hasCurrentViewer && resource.value != nil && !resource.isLoading }
    private var contextComment: ProfileComment? { comment?.location == nil ? parent.value ?? comment : comment }
    private var threadRoot: ProfileComment? { rootID == commentID ? comment : parent.value }
    private var errorMessage: String? { actionError ?? composer.errorMessage }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ProfileViewerNotice(viewer: composer.viewer)
                if hasCurrentViewer, let comment {
                    if let location {
                        Section {
                            NavigationLink {
                                ProfileCommentParentDestination(location: location, comment: contextComment, viewer: composer.viewer)
                            } label: { Text(ProfileCommentPresentation.parentTitle(contextComment ?? comment)).font(.ax(.subheadline)) }
                        }
                    }
                    ProfileCommentSortHeader(totalCount: replies?.totalCount, sort: $sort)
                    if let root = threadRoot {
                        Section {
                            ProfileCommentRow(comment: root, viewer: composer.viewer, onReply: { chooseReply(root) },
                                               onVote: { value in Task { await vote(root, value) } },
                                               isVoting: votingIDs.contains(root.id), actionsEnabled: actionsEnabled,
                                               contextCategory: category)
                        }
                    }
                    if let replies {
                        Section {
                            PaginatedContent(paginator: replies, emptyTitle: "Ответов пока нет") { reply in
                                if reply.id != rootID {
                                    ProfileCommentRow(comment: reply, viewer: composer.viewer, onReply: { chooseReply(reply) },
                                                       onVote: { value in Task { await vote(reply, value) } },
                                                       isVoting: votingIDs.contains(reply.id), actionsEnabled: actionsEnabled,
                                                       contextCategory: category, isReply: true)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                    ProfileSaveError(message: resource.errorMessage ?? parent.errorMessage)
                } else if composer.viewer == nil || hasCurrentViewer {
                    ProfileResourceState(resource: resource, title: "Не удалось загрузить комментарий", retry: load)
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
            if hasCurrentViewer, location != nil, comment?.isDeleted != true {
                ProfileCommentComposer(draft: $composer.message, isSpoiler: $composer.isSpoiler, viewer: composer.viewer,
                                       replyingTo: composer.replyingTo?.profile?.login,
                                       isSending: composer.isSending || !actionsEnabled,
                                       onCancelReply: { composer.replyingTo = nil }, onSend: { Task { await send() } })
            }
        }
        .navigationTitle("Ответы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: sort) { await load() }
        .onChange(of: env.session.viewerKey) { _, current in
            guard let viewer = composer.viewer, viewer != current else { return }
            composer.invalidate(for: current)
            loadGeneration += 1
            resource.reset()
            parent.reset()
            replies = nil
            repliesRootID = nil
            loadedRepliesSort = nil
            actionError = nil
        }
        .alert("Комментарии", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { clearError() } })) {
            Button("Понятно", role: .cancel) { clearError() }
        } message: { Text(errorMessage ?? "") }
    }

    private func clearError() { actionError = nil; composer.errorMessage = nil }
    private func load() async { await loadThread(refreshReplies: false) }
    private func refresh() async { await loadThread(refreshReplies: true) }

    private func loadThread(refreshReplies: Bool) async {
        let viewer = composer.captureViewer(env.session.viewerKey)
        guard viewer == env.session.viewerKey else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let loaded = await resource.load {
            let response = try await env.session.sendViewerRequest(ProfileCommentEndpoints.comment(id: commentID, category: category), for: viewer)
            guard response.id == commentID, response.id > 0, response.category == nil || response.category == category else {
                throw AnixartError.decoding(message: "Ответ не содержит комментарий", path: "comment/\(commentID)")
            }
            return response
        }
        guard generation == loadGeneration, viewer == env.session.viewerKey, !Task.isCancelled,
              let comment = loaded ?? resource.value else { return }
        let root = comment.threadRootID
        if root != commentID {
            if parent.value?.id != root { parent.reset() }
            await parent.load {
                let response = try await env.session.sendViewerRequest(ProfileCommentEndpoints.comment(id: root, category: category), for: viewer)
                guard response.id == root, response.category == nil || response.category == category else {
                    throw AnixartError.decoding(message: "Ответ не содержит исходный комментарий", path: "comment/\(root)")
                }
                return response
            }
        } else { parent.reset() }
        guard generation == loadGeneration, viewer == env.session.viewerKey, !Task.isCancelled else { return }
        if repliesRootID != root || loadedRepliesSort != sort {
            let session = env.session
            let category = self.category
            let sort = self.sort
            replies = Paginator { page in
                try await session.sendViewerRequest(ProfileCommentEndpoints.replies(commentID: root, category: category, page: page, sort: sort.rawValue), for: viewer)
            }
            repliesRootID = root
            loadedRepliesSort = sort
        }
        if refreshReplies { await replies?.reload() }
        else { await replies?.loadFirstPageIfNeeded() }
    }

    private func chooseReply(_ comment: ProfileComment) {
        guard actionsEnabled, !composer.isSending, comment.isDeleted != true else { return }
        composer.replyingTo = comment
    }

    private func vote(_ comment: ProfileComment, _ value: CommentVote) async {
        guard actionsEnabled, let viewer = composer.viewer, viewer == env.session.viewerKey,
              !votingIDs.contains(comment.id), comment.isDeleted != true, comment.canLike != false else { return }
        guard let account = viewer.account else { env.session.promptSignIn(); return }
        votingIDs.insert(comment.id)
        actionError = nil
        let list = replies
        defer { votingIDs.remove(comment.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileCommentEndpoints.vote(commentID: comment.id, category: category, vote: value), for: account)
            if comment.id == commentID || comment.id == rootID { await refresh() }
            else { await list?.reload() }
        } catch {
            if !ProfileRequestFailure.isCancellation(error) { actionError = Paginator<Release>.message(for: error) }
        }
    }

    private func send() async {
        guard actionsEnabled, let location, let account = composer.viewer?.account else { return }
        if await composer.send(at: location, parentCommentID: rootID,
                               defaultReplyToProfileID: comment?.profile?.id, session: env.session) {
            await refresh()
            await env.session.refreshProfile(for: account)
        }
    }
}

@MainActor
struct ProfileCommentsAtLocationView: View {
    @Environment(AppEnvironment.self) private var env
    let location: ProfileCommentLocation
    @State private var paginator: Paginator<ProfileComment>?
    @State private var composer: ProfileCommentDraft
    @State private var sort: ProfileCommentSort = .newest
    @State private var votingIDs = Set<Int>()
    @State private var actionError: String?

    init(location: ProfileCommentLocation, viewer: ProfileViewerKey? = nil) {
        self.location = location
        _composer = State(initialValue: ProfileCommentDraft(viewer: viewer))
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ProfileViewerNotice(viewer: composer.viewer)
                if composer.viewer == env.session.viewerKey, let paginator {
                    ProfileCommentSortHeader(totalCount: paginator.totalCount, sort: $sort)
                    PaginatedContent(paginator: paginator, emptyTitle: "Комментариев пока нет") { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            ProfileCommentRow(comment: comment, viewer: composer.viewer,
                                              onReply: { if !composer.isSending { composer.replyingTo = comment } },
                                              onVote: { value in Task { await vote(comment, value: value) } },
                                              isVoting: votingIDs.contains(comment.id), actionsEnabled: !composer.isSending,
                                              contextCategory: location.category)
                            if let count = comment.replyCount, count > 0 {
                                NavigationLink("Показать \(Plural.replies(count))") {
                                    ProfileCommentDetailView(commentID: comment.threadRootID, category: location.category,
                                                             preloaded: comment.threadRootID == comment.id ? comment : nil,
                                                             fallbackLocation: location, viewer: composer.viewer)
                                }
                                .font(.ax(.subheadline)).padding(.leading, 52)
                            }
                        }
                    }
                    ProfileSaveError(message: actionError)
                }
            }
            .listStyle(.plain)
            .refreshable { await paginator?.reload() }
            ProfileCommentComposer(draft: $composer.message, isSpoiler: $composer.isSpoiler, viewer: composer.viewer,
                                   replyingTo: composer.replyingTo?.profile?.login,
                                   isSending: composer.isSending,
                                   onCancelReply: { composer.replyingTo = nil },
                                   onSend: { Task { await send() } })
        }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: sort) {
            let viewer = composer.captureViewer(env.session.viewerKey)
            guard viewer == env.session.viewerKey else { return }
            let session = env.session
            let location = self.location
            let sort = self.sort
            paginator = Paginator { page in try await session.sendViewerRequest(ProfileCommentEndpoints.all(at: location, page: page, sort: sort.rawValue), for: viewer) }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            composer.invalidate(for: current)
            if composer.viewer != current { paginator = nil; actionError = nil }
        }
        .alert("Не удалось отправить", isPresented: Binding(get: { composer.errorMessage != nil }, set: { if !$0 { composer.errorMessage = nil } })) {
            Button("Понятно", role: .cancel) { composer.errorMessage = nil }
        } message: { Text(composer.errorMessage ?? "") }
    }

    private func send() async {
        guard let account = composer.viewer?.account else { env.session.promptSignIn(); return }
        let list = paginator
        if await composer.send(at: location, parentCommentID: composer.replyingTo?.threadRootID, session: env.session) {
            await list?.reload()
            await env.session.refreshProfile(for: account)
        }
    }

    private func vote(_ comment: ProfileComment, value: CommentVote) async {
        guard composer.viewer == env.session.viewerKey, !composer.isSending,
              !votingIDs.contains(comment.id), comment.isDeleted != true, comment.canLike != false else { return }
        guard let account = composer.viewer?.account else { env.session.promptSignIn(); return }
        votingIDs.insert(comment.id)
        actionError = nil
        defer { votingIDs.remove(comment.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(ProfileCommentEndpoints.vote(commentID: comment.id,
                                                                                         category: location.category,
                                                                                          vote: value), for: account)
            await paginator?.reload()
        } catch { if !ProfileRequestFailure.isCancellation(error) { actionError = Paginator<Release>.message(for: error) } }
    }
}

@MainActor
struct ProfileCommentRow: View {
    let comment: ProfileComment
    var viewer: ProfileViewerKey?
    var onReply: (() -> Void)?
    var onVote: ((CommentVote) -> Void)?
    var isVoting = false
    var actionsEnabled = true
    var contextCategory: ProfileCommentCategory?
    /// Reddit-style reply: indented under a thread line, compact header, actions below.
    var isReply = false
    @State private var revealsSpoiler = false

    var body: some View {
        if isReply { replyBody } else { fullBody }
    }

    private var replyBody: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let profile = comment.profile {
                        NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: {
                            HStack(spacing: 8) {
                                Avatar(url: AnixartURL.image(profile.avatar), size: 24)
                                Text(profile.login ?? "Пользователь").font(.ax(.footnote, .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        if profile.isSponsor == true { Image(systemName: "crown.fill").font(.ax(.caption2)).foregroundStyle(Theme.sponsorGold) }
                    } else { Text("Пользователь").font(.ax(.footnote, .medium)) }
                    Text("· " + (Format.relativeDate(comment.date) ?? ProfileDate.text(comment.timestamp)) + (comment.isEdited == true ? " · изменён" : ""))
                        .font(.ax(.caption)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if comment.isDeleted == true {
                    Text("Комментарий удалён").font(.ax(.subheadline)).foregroundStyle(.secondary)
                } else if comment.isSpoiler == true, !revealsSpoiler {
                    Button { revealsSpoiler = true } label: {
                        Label("Спойлер — нажмите, чтобы прочитать", systemImage: "eye.slash")
                            .font(.ax(.caption)).foregroundStyle(.secondary)
                            .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(comment.message ?? "").font(.ax(.subheadline))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if comment.isDeleted != true {
                    HStack(spacing: 6) {
                        voteButton(.positive, icon: "arrow.up")
                        Text(Format.count(comment.voteCount)).monospacedDigit().foregroundStyle(.secondary)
                        voteButton(.negative, icon: "arrow.down")
                        if let onReply {
                            Button(action: onReply) {
                                Label("Ответить", systemImage: "arrowshape.turn.up.left")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .disabled(!actionsEnabled)
                            .padding(.leading, 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.ax(.caption, .medium))
                }
            }
        }
        .padding(.vertical, 6)
        .profileCommentContext(comment, category: contextCategory ?? comment.category, viewer: viewer)
    }

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 12) {
            if let profile = comment.profile {
                NavigationLink { ProfileView(profileID: profile.id, viewer: viewer) } label: { Avatar(url: AnixartURL.image(profile.avatar), size: 40) }
                    .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let profile = comment.profile {
                        NavigationLink(profile.login ?? "Пользователь") { ProfileView(profileID: profile.id, viewer: viewer) }.buttonStyle(.plain)
                        if let url = AnixartURL.image(profile.badgeUrl) {
                            CachedAsyncImage(url: url, maxPixelSize: 80) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                                .frame(width: 20, height: 20)
                        }
                        if profile.isSponsor == true { Image(systemName: "crown.fill").foregroundStyle(Theme.sponsorGold) }
                    } else { Text("Пользователь") }
                    Spacer(minLength: 0)
                }
                .font(.ax(.subheadline, .medium))
                Text((Format.relativeDate(comment.date) ?? ProfileDate.text(comment.timestamp)) + (comment.isEdited == true ? " • изменён" : ""))
                    .font(.ax(.caption)).foregroundStyle(.secondary)
                if comment.isDeleted == true {
                    Text("Комментарий удалён").font(.ax(.subheadline)).foregroundStyle(.secondary)
                } else if comment.isSpoiler == true, !revealsSpoiler {
                    Button { revealsSpoiler = true } label: {
                        Label("Содержит спойлер — нажмите, чтобы прочитать", systemImage: "eye.slash")
                            .font(.ax(.subheadline)).foregroundStyle(.secondary)
                            .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(comment.message ?? "").font(.ax(.subheadline)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let episode = comment.postedAtEpisode, episode > 0 {
                    Text("На момент выхода \(episode) серии").font(.ax(.caption)).foregroundStyle(.secondary)
                }
                if comment.isDeleted != true {
                    HStack(spacing: 14) {
                        if let onReply {
                            Button("Ответить", action: onReply).buttonStyle(.plain).foregroundStyle(.secondary)
                                .disabled(!actionsEnabled)
                        }
                        Spacer(minLength: 0)
                        voteButton(.negative, icon: "chevron.down")
                        Text(Format.count(comment.voteCount)).monospacedDigit()
                        voteButton(.positive, icon: "chevron.up")
                    }
                    .font(.ax(.subheadline))
                }
            }
        }
        .padding(.vertical, 8)
        .profileCommentContext(comment, category: contextCategory ?? comment.category, viewer: viewer)
    }

    private func voteButton(_ value: CommentVote, icon: String) -> some View {
        Button { onVote?(value) } label: {
            Image(systemName: icon).foregroundStyle(value.isSelected(currentVote: comment.vote) ? Theme.accent : Color.secondary)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!actionsEnabled || onVote == nil || isVoting || comment.canLike == false)
        .accessibilityLabel(value == .positive ? "Нравится" : "Не нравится")
    }
}

@MainActor
struct ProfileCommentComposer: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var draft: String
    @Binding var isSpoiler: Bool
    let viewer: ProfileViewerKey?
    var replyingTo: String?
    var isSending: Bool
    var onCancelReply: (() -> Void)?
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if let viewer, viewer != env.session.viewerKey {
                Text("Сессия изменилась. Откройте комментарии заново.")
                    .font(.ax(.subheadline)).foregroundStyle(.secondary).padding()
            } else if viewer?.account != nil {
                if let replyingTo {
                    HStack {
                        Text("Ответ \(replyingTo)").font(.ax(.caption)).foregroundStyle(.secondary)
                        Button { onCancelReply?() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Отменить ответ")
                            .disabled(isSending)
                    }
                    .padding(.horizontal)
                }
                TextField("Ваш комментарий", text: $draft, axis: .vertical).font(.ax(.body)).lineLimit(1...4).padding(.horizontal)
                    .disabled(isSending)
                HStack(spacing: 14) {
                    Button { isSpoiler.toggle() } label: {
                        Label("Спойлер", systemImage: isSpoiler ? "eye.slash.fill" : "eye.slash")
                            .foregroundStyle(isSpoiler ? Theme.accent : Color.primary)
                    }
                    .buttonStyle(.plain)
                    Link("Правила", destination: AnixartEnvironment.webBaseURL.appendingPathComponent("rules"))
                    Spacer()
                    Button(action: onSend) {
                        Group { if isSending { ProgressView() } else { Image(systemName: "arrow.up") } }
                            .frame(width: 44, height: 44).background(Color.primary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Отправить комментарий")
                }
                .font(.ax(.subheadline)).padding(.horizontal).padding(.bottom, 10)
                .disabled(isSending)
            } else {
                Button("Войдите, чтобы комментировать") { env.session.promptSignIn() }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
        .background(.bar)
    }
}

@MainActor
struct ProfileCommentParentDestination: View {
    let location: ProfileCommentLocation
    var comment: ProfileComment?
    var viewer: ProfileViewerKey?
    var body: some View {
        switch location.category {
        case .releases:
            ReleaseDetailView(releaseID: location.parentID, preloaded: comment?.release?.value, viewer: viewer)
        case .collections:
            ProfileCollectionDestination(collectionID: location.parentID, preloaded: comment?.collection?.value, viewer: viewer)
        case .articles:
            ProfileArticleView(articleID: location.parentID, preloaded: comment?.article?.value, viewer: viewer)
        }
    }
}

@MainActor
struct ProfileCollectionDestination: View {
    @Environment(AppEnvironment.self) private var env
    let collectionID: Int
    var preloaded: ReleaseCollection?
    @State private var viewer: ProfileViewerKey?
    @State private var resource = ProfileResource<CollectionResponse>()

    init(collectionID: Int, preloaded: ReleaseCollection? = nil, viewer: ProfileViewerKey? = nil) {
        self.collectionID = collectionID
        self.preloaded = preloaded?.id == collectionID ? preloaded : nil
        _viewer = State(initialValue: viewer)
    }

    var body: some View {
        Group {
            if let viewer, viewer != env.session.viewerKey {
                ProfileViewerNotice(viewer: viewer)
            } else if viewer == env.session.viewerKey, let collection = resource.value?.collection ?? preloaded {
                CollectionDetailView(collection: collection, viewer: viewer)
            } else {
                ProfileResourceState(resource: resource, title: "Не удалось загрузить коллекцию", retry: load)
            }
        }
        .navigationTitle("Коллекция")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            if viewer == nil { viewer = env.session.viewerKey }
            await load()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            if viewer != current { resource.reset() }
        }
    }

    private func load() async {
        guard let viewer, viewer == env.session.viewerKey else { return }
        await resource.load {
            let response = try await env.session.sendViewerRequest(CollectionEndpoints.collection(id: collectionID), for: viewer)
            guard response.collection?.id == collectionID else {
                throw AnixartError.decoding(message: "Ответ не содержит коллекцию", path: "collection/\(collectionID)")
            }
            return response
        }
    }
}
