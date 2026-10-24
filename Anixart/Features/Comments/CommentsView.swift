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

    var body: some View {
        VStack(spacing: 0) {
            List {
                if let paginator {
                    PaginatedContent(
                        paginator: paginator,
                        emptyTitle: "Нет комментариев",
                        emptyMessage: "Будьте первым, кто поделится впечатлением"
                    ) { comment in
                        CommentRow(comment: comment)
                    }
                }
            }
            .listStyle(.plain)

            composer
        }
        .navigationTitle("Комментарии")
        .navigationBarTitleDisplayMode(.inline)
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

    private var composer: some View {
        VStack(spacing: 8) {
            Divider()
            if env.session.isSignedIn {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Поделитесь впечатлениями", text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                        Toggle("Содержит спойлер", isOn: $isSpoiler)
                            .font(.caption)
                            .toggleStyle(.button)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            } else {
                Button("Войдите, чтобы комментировать") { env.session.promptSignIn() }
                    .font(.subheadline)
                    .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return }
        isSending = true
        do {
            _ = try await env.client.send(
                CommentEndpoints.add(
                    releaseID: releaseID,
                    CommentAddRequest(message: message, spoiler: isSpoiler)
                )
            )
            draft = ""
            isSpoiler = false
            await paginator?.reload()
        } catch {
            sendError = Paginator<Release>.message(for: error)
        }
        isSending = false
    }
}

/// One comment. Spoilers stay hidden until tapped, as in the Android app.
@MainActor
struct CommentRow: View {
    let comment: ReleaseComment
    var showsRelease = false

    @State private var isSpoilerRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AsyncImage(url: comment.authorAvatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(comment.authorLogin).font(.caption.weight(.medium))
                    if let date = Format.relativeDate(comment.postedAt) {
                        Text(date).font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let votes = comment.voteCount, votes != 0 {
                    Label(Format.count(votes), systemImage: votes > 0 ? "arrow.up" : "arrow.down")
                        .labelStyle(.compact)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // `discover/comments` inlines the release the comment belongs to, which is
            // what makes a comment legible outside its own release page.
            if showsRelease, let release = comment.release {
                Text(release.displayTitle).font(.caption2).foregroundStyle(Theme.accent)
            }

            if comment.containsSpoiler && !isSpoilerRevealed {
                Button {
                    withAnimation { isSpoilerRevealed = true }
                } label: {
                    Label("Содержит спойлер — нажмите, чтобы прочитать", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Text(comment.message ?? "")
                    .font(.subheadline)
                    .textSelection(.enabled)
            }

            if let replies = comment.replyCount, replies > 0 {
                Text("Ответов: \(Format.count(replies))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
