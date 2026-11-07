import SwiftUI
import AnixartKit

/// All comments for a release, with a composer at the bottom.
@MainActor
struct CommentsView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    let releaseTitle: String
    let initialReplyTo: ReleaseComment?

    @State private var paginator: Paginator<ReleaseComment>?
    @State private var sort = ProfileCommentSort.newest.rawValue
    @State private var composer: ProfileCommentDraft
    @State private var votingIDs = Set<Int>()
    @State private var actionError: String?
    @State private var openThread: ReleaseComment?

    init(releaseID: Int, releaseTitle: String, viewer: ProfileViewerKey? = nil,
         initialReplyTo: ReleaseComment? = nil) {
        self.releaseID = releaseID
        self.releaseTitle = releaseTitle
        self.initialReplyTo = initialReplyTo
        _composer = State(initialValue: ProfileCommentDraft(viewer: viewer))
    }

    private var hasCurrentViewer: Bool { composer.viewer == env.session.viewerKey }
    private var errorMessage: String? { actionError ?? composer.errorMessage }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ProfileViewerNotice(viewer: composer.viewer)
                if hasCurrentViewer, let paginator {
                    PaginatedContent(
                        paginator: paginator,
                        emptyTitle: "Нет комментариев",
                        emptyMessage: "Будьте первым, кто поделится впечатлением"
                    ) { comment in
                        CommentRow(
                            comment: comment,
                            onReply: { if !composer.isSending { composer.replyingTo = ProfileComment(releaseComment: comment) } },
                            onVote: { vote in Task { await self.vote(comment, vote) } },
                            onOpenReplies: { openThread = comment },
                            isVoting: votingIDs.contains(comment.id),
                            actionsEnabled: !composer.isSending
                        )
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await paginator?.reload() }

            composerView
        }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openThread) { comment in
            CommentThreadView(comment: comment, releaseID: releaseID, viewer: composer.viewer)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(ProfileCommentSort.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: sort) {
            let viewer = composer.captureViewer(env.session.viewerKey)
            guard viewer == env.session.viewerKey else { return }
            if composer.replyingTo == nil, let initialReplyTo {
                composer.replyingTo = ProfileComment(releaseComment: initialReplyTo)
            }
            let session = env.session
            let id = releaseID
            let currentSort = sort
            paginator = Paginator { page in
                try await session.sendViewerRequest(CommentEndpoints.comments(releaseID: id, page: page, sort: currentSort), for: viewer)
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .onChange(of: env.session.viewerKey) { _, current in
            composer.invalidate(for: current)
            if composer.viewer != current { paginator = nil; openThread = nil; actionError = nil }
        }
        .alert("Комментарии", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { clearError() } }
        )) {
            Button("Понятно", role: .cancel) { clearError() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// The composer, laid out as the Android one is: the field, a Спойлер toggle
    /// and a Правила link, and a round send button on the right.
    private var composerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if let viewer = composer.viewer, viewer != env.session.viewerKey {
                Text("Сессия изменилась. Откройте комментарии заново.")
                    .font(.ax(.subheadline)).foregroundStyle(.secondary).padding()
            } else if composer.viewer?.account != nil {
                if let replyingTo = composer.replyingTo {
                    HStack(spacing: 8) {
                        Text("Ответ \(replyingTo.profile?.login ?? "Пользователь")")
                            .font(.ax(.caption))
                            .foregroundStyle(.secondary)
                        Button {
                            composer.replyingTo = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(composer.isSending)
                    }
                    .padding(.horizontal)
                }

                TextField("Ваш комментарий", text: $composer.message, axis: .vertical)
                    .font(.ax(.title3))
                    .lineLimit(1...4)
                    .padding(.horizontal)
                    .disabled(composer.isSending)

                HStack(spacing: 12) {
                    Button {
                        composer.isSpoiler.toggle()
                    } label: {
                        Label("Спойлер", systemImage: composer.isSpoiler ? "eye.slash.fill" : "eye.slash")
                            .font(.ax(.subheadline))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                if composer.isSpoiler {
                                    Capsule().fill(Theme.accent.opacity(0.22))
                                } else {
                                    Capsule().stroke(.quaternary, lineWidth: 1)
                                }
                            }
                            .foregroundStyle(composer.isSpoiler ? Theme.accent : .primary)
                    }
                    .buttonStyle(.plain)

                    Link(destination: URL(string: "https://anixart-app.com/rules/")!) {
                        Label("Правила", systemImage: "list.clipboard")
                            .font(.ax(.subheadline))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .overlay(Capsule().stroke(.quaternary, lineWidth: 1))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Button {
                        Task { await send() }
                    } label: {
                        Group {
                            if composer.isSending {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up").font(.ax(.headline))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.12), in: Circle())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(composer.isSending || composer.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(composer.isSending)
            } else {
                Button("Войдите, чтобы комментировать") { env.session.promptSignIn() }
                    .font(.ax(.subheadline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    /// The server toggles repeated `1` / `2` requests, as the Android arrows do.
    private func vote(_ comment: ReleaseComment, _ vote: CommentVote) async {
        guard hasCurrentViewer, !votingIDs.contains(comment.id), comment.isDeleted != true, comment.canLike != false else { return }
        guard let account = composer.viewer?.account else {
            env.session.promptSignIn()
            return
        }
        votingIDs.insert(comment.id)
        actionError = nil
        let list = paginator
        defer { votingIDs.remove(comment.id) }
        do {
            try await env.session.sendConfirmedAccountRequest(CommentEndpoints.vote(commentID: comment.id, vote: vote), for: account)
            AppHaptics.shared.play(.voteCast)
            await list?.reload()
        } catch {
            if hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) {
                actionError = Paginator<Release>.message(for: error)
                AppHaptics.shared.play(.error)
            }
        }
    }

    private func send() async {
        let list = paginator
        let account = composer.viewer?.account
        let location = ProfileCommentLocation(category: .releases, parentID: releaseID)
        if await composer.send(at: location, parentCommentID: composer.replyingTo?.threadRootID, session: env.session) {
            AppHaptics.shared.play(.commentSent)
            await list?.reload()
            if let account { await env.session.refreshProfile(for: account) }
        } else {
            AppHaptics.shared.play(.commentFailed)
        }
    }

    private func clearError() { actionError = nil; composer.errorMessage = nil }
}

/// One comment, laid out as the Android list lays it out: avatar beside the
/// author and time, the message, the episode it was written at, then the reply
/// action and the vote arrows. Spoilers stay hidden until tapped.
@MainActor
struct CommentRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DeviceAppearancePreferenceKey.resourceSaving) private var resourceSaving = false
    let comment: ReleaseComment
    var showsRelease = false
    var onReply: (() -> Void)?
    var onVote: ((CommentVote) -> Void)?
    var onOpenReplies: (() -> Void)?
    var isVoting = false
    var actionsEnabled = true

    @State private var isSpoilerRevealed = false

    private var motion: AppMotionPolicy { AppMotionPolicy(reduceMotion: reduceMotion, resourceSaving: resourceSaving) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: comment.authorAvatarURL, size: 40)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(comment.authorLogin).font(.ax(.subheadline, .medium))
                    if let date = Format.relativeDate(comment.postedAt) {
                        Text(date).font(.ax(.subheadline)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                // `discover/comments` inlines the release the comment belongs to, which is
                // what makes a comment legible outside its own release page.
                if showsRelease, let release = comment.release?.value {
                    Text(release.displayTitle).font(.ax(.caption)).foregroundStyle(Theme.accent)
                }

                if comment.isDeleted == true {
                    Text("Комментарий удалён").font(.ax(.subheadline)).foregroundStyle(.secondary)
                } else if comment.containsSpoiler && !isSpoilerRevealed {
                    Button { revealSpoiler() } label: {
                        Label("Содержит спойлер — нажмите, чтобы прочитать", systemImage: "eye.slash")
                            .font(.ax(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .onKeyPress(.return) { revealSpoiler(fromKeyboard: true); return .handled }
                    .onKeyPress(.space) { revealSpoiler(fromKeyboard: true); return .handled }
                } else {
                    Text(comment.message ?? "")
                        .font(.ax(.subheadline))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let episode = comment.postedAtEpisode, episode > 0 {
                    Text("На момент выхода \(episode) серии")
                        .font(.ax(.caption))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    if let onReply {
                        Button("Ответить", action: onReply)
                            .font(.ax(.subheadline))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .disabled(!actionsEnabled || comment.isDeleted == true)
                    }
                    Spacer(minLength: 0)
                    voteControls
                }
                .padding(.top, 2)

                if let replies = comment.replyCount, replies > 0 {
                    Button {
                        onOpenReplies?()
                    } label: {
                        Label("Показать \(Plural.replies(replies))", systemImage: "chevron.right")
                            .labelStyle(.trailingIcon)
                            .font(.ax(.subheadline, .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(onOpenReplies == nil)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func revealSpoiler(fromKeyboard: Bool = false) {
        guard !isSpoilerRevealed, comment.isDeleted != true, comment.containsSpoiler else { return }
        motion.perform(animated: !fromKeyboard, using: .default) { isSpoilerRevealed = true }
    }

    /// The down / score / up triple. The score takes the colour of the viewer's
    /// own vote, which is how the Android row shows what you pressed.
    private var voteControls: some View {
        HStack(spacing: 14) {
            Button {
                onVote?(.negative)
            } label: {
                Image(systemName: "chevron.down")
                    .foregroundStyle(CommentVote.negative.isSelected(currentVote: comment.vote) ? Theme.newBadge : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!actionsEnabled || onVote == nil || isVoting || comment.isDeleted == true || comment.canLike == false)

            Text(Format.count(comment.voteCount))
                .font(.ax(.subheadline, .medium))
                .monospacedDigit()
                .foregroundStyle(voteColor)

            Button {
                onVote?(.positive)
            } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(CommentVote.positive.isSelected(currentVote: comment.vote) ? Theme.listColor(.watching) : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!actionsEnabled || onVote == nil || isVoting || comment.isDeleted == true || comment.canLike == false)
        }
    }

    private var voteColor: Color {
        if CommentVote.positive.isSelected(currentVote: comment.vote) { return Theme.listColor(.watching) }
        if CommentVote.negative.isSelected(currentVote: comment.vote) { return Theme.newBadge }
        return (comment.voteCount ?? 0) > 0 ? Theme.listColor(.watching) : .secondary
    }
}

/// Label with the icon after the text, for "Показать N ответов".
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.ax(.caption))
        }
    }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}

/// The replies under one comment.
@MainActor
struct CommentThreadView: View {
    let comment: ReleaseComment
    let releaseID: Int
    var viewer: ProfileViewerKey?

    var body: some View {
        ProfileCommentDetailView(commentID: comment.id, category: .releases,
                                 preloaded: ProfileComment(releaseComment: comment),
                                 fallbackLocation: ProfileCommentLocation(category: .releases, parentID: releaseID), viewer: viewer)
    }
}