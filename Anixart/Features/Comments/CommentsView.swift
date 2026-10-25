import SwiftUI
import AnixartKit

/// All comments for a release, with a composer at the bottom.
@MainActor
struct CommentsView: View {
    @Environment(AppEnvironment.self) private var env

    let releaseID: Int
    let releaseTitle: String

    @State private var paginator: Paginator<ReleaseComment>?
    @State private var sort = 0
    @State private var draft = ""
    @State private var isSpoiler = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var replyingTo: ReleaseComment?
    @State private var openThread: ReleaseComment?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let paginator {
                    PaginatedContent(
                        paginator: paginator,
                        emptyTitle: "Нет комментариев",
                        emptyMessage: "Будьте первым, кто поделится впечатлением"
                    ) { comment in
                        CommentRow(
                            comment: comment,
                            onReply: { replyingTo = comment },
                            onVote: { vote in Task { await self.vote(comment, vote) } },
                            onOpenReplies: { openThread = comment }
                        )
                    }
                }
            }
            .listStyle(.plain)

            composer
        }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openThread) { comment in
            CommentThreadView(comment: comment, releaseID: releaseID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Сортировка", selection: $sort) {
                        Text("Сначала новые").tag(0)
                        Text("Сначала старые").tag(1)
                        Text("Сначала популярные").tag(2)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: sort) {
            let client = env.client
            let id = releaseID
            let currentSort = sort
            paginator = Paginator { page in
                try await client.send(CommentEndpoints.comments(releaseID: id, page: page, sort: currentSort))
            }
            await paginator?.loadFirstPageIfNeeded()
        }
        .alert("Не удалось отправить", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) {
            Button("Понятно", role: .cancel) { sendError = nil }
        } message: {
            Text(sendError ?? "")
        }
    }

    /// The composer, laid out as the Android one is: the field, a Спойлер toggle
    /// and a Правила link, and a round send button on the right.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if env.session.isSignedIn {
                if let replyingTo {
                    HStack(spacing: 8) {
                        Text("Ответ \(replyingTo.authorLogin)")
                            .font(.ax(.caption))
                            .foregroundStyle(.secondary)
                        Button {
                            self.replyingTo = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }

                TextField("Ваш комментарий", text: $draft, axis: .vertical)
                    .font(.ax(.title3))
                    .lineLimit(1...4)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        isSpoiler.toggle()
                    } label: {
                        Label("Спойлер", systemImage: isSpoiler ? "eye.slash.fill" : "eye.slash")
                            .font(.ax(.subheadline))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background {
                                if isSpoiler {
                                    Capsule().fill(Theme.accent.opacity(0.22))
                                } else {
                                    Capsule().stroke(.quaternary, lineWidth: 1)
                                }
                            }
                            .foregroundStyle(isSpoiler ? Theme.accent : .primary)
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
                            if isSending {
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
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                Button("Войдите, чтобы комментировать") { env.session.promptSignIn() }
                    .font(.ax(.subheadline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    /// Up- or down-votes a comment. `vote` is 1 or -1, and repeating the same
    /// vote clears it, which is what the Android arrows do.
    private func vote(_ comment: ReleaseComment, _ vote: Int) async {
        guard env.session.isSignedIn else {
            env.session.promptSignIn()
            return
        }
        let value = (comment.vote ?? 0) == vote ? 0 : vote
        _ = try? await env.client.send(CommentEndpoints.vote(commentID: comment.id, vote: value))
        await paginator?.reload()
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        isSending = true
        do {
            _ = try await env.client.send(
                CommentEndpoints.add(
                    releaseID: releaseID,
                    CommentAddRequest(
                        message: message,
                        parentCommentId: replyingTo?.id,
                        replyToProfileId: replyingTo?.profile?.id,
                        spoiler: isSpoiler
                    )
                )
            )
            draft = ""
            isSpoiler = false
            replyingTo = nil
            await paginator?.reload()
        } catch {
            sendError = Paginator<Release>.message(for: error)
        }
        isSending = false
    }
}

/// One comment, laid out as the Android list lays it out: avatar beside the
/// author and time, the message, the episode it was written at, then the reply
/// action and the vote arrows. Spoilers stay hidden until tapped.
@MainActor
struct CommentRow: View {
    let comment: ReleaseComment
    var showsRelease = false
    var onReply: (() -> Void)?
    var onVote: ((Int) -> Void)?
    var onOpenReplies: (() -> Void)?

    @State private var isSpoilerRevealed = false

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
                if showsRelease, let release = comment.release {
                    Text(release.displayTitle).font(.ax(.caption)).foregroundStyle(Theme.accent)
                }

                if comment.containsSpoiler && !isSpoilerRevealed {
                    Button {
                        withAnimation { isSpoilerRevealed = true }
                    } label: {
                        Label("Содержит спойлер — нажмите, чтобы прочитать", systemImage: "eye.slash")
                            .font(.ax(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
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

    /// The down / score / up triple. The score takes the colour of the viewer's
    /// own vote, which is how the Android row shows what you pressed.
    private var voteControls: some View {
        HStack(spacing: 14) {
            Button {
                onVote?(-1)
            } label: {
                Image(systemName: "chevron.down").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(onVote == nil)

            Text(Format.count(comment.voteCount))
                .font(.ax(.subheadline, .medium))
                .monospacedDigit()
                .foregroundStyle(voteColor)

            Button {
                onVote?(1)
            } label: {
                Image(systemName: "chevron.up").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(onVote == nil)
        }
    }

    private var voteColor: Color {
        switch comment.vote ?? 0 {
        case 1...: return Theme.listColor(.watching)
        case ..<0: return Theme.newBadge
        default: return (comment.voteCount ?? 0) > 0 ? Theme.listColor(.watching) : .secondary
        }
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
    @Environment(AppEnvironment.self) private var env

    let comment: ReleaseComment
    let releaseID: Int

    @State private var paginator: Paginator<ReleaseComment>?

    var body: some View {
        List {
            CommentRow(comment: comment)
            if let paginator {
                PaginatedContent(paginator: paginator, emptyTitle: "Ответов пока нет") { reply in
                    CommentRow(comment: reply)
                        .padding(.leading, 28)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Ответы")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if paginator == nil {
                let client = env.client
                let id = comment.id
                paginator = Paginator { page in
                    try await client.send(CommentEndpoints.replies(commentID: id, page: page))
                }
            }
            await paginator?.loadFirstPageIfNeeded()
        }
    }
}
