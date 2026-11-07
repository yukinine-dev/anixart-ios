import SwiftUI
import AnixartKit

@MainActor
struct FeedChannelCarousel: View {
    let channels: [Channel]
    let viewer: ProfileViewerKey
    let actions: FeedActionsModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(channels) { source in
                    let channel = actions.channel(source)
                    VStack(spacing: 8) {
                        NavigationLink(value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: viewer)) {
                            VStack(spacing: 8) {
                                Avatar(url: AnixartURL.image(channel.avatar), size: 80)
                                Text(channel.title ?? "Канал").font(.ax(.subheadline)).lineLimit(1)
                                Text("\(Format.count(channel.subscriberCount)) подписчиков").font(.ax(.caption)).foregroundStyle(.secondary).lineLimit(1)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if channel.isSubscribed == true {
                            Text(actions.blogRequestsSent.contains(channel.id) ? "Заявка отправлена" : "Вы подписаны")
                                .font(.ax(.caption)).foregroundStyle(.secondary).frame(minHeight: 44)
                        } else {
                            FeedSubscribeButton(channel: channel, actions: actions)
                        }
                    }.frame(width: 120)
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

@MainActor
struct FeedChannelListContent: View {
    let model: FeedChannelListModel
    let actions: FeedActionsModel
    var observesMembershipChanges = true
    @State private var unsubscribeTarget: Channel?

    var body: some View {
        List {
            if model.hasCurrentViewer, actions.viewer == model.viewer {
                if let error = actions.errorMessage { Text(error).font(.ax(.subheadline)).foregroundStyle(.red) }
                PaginatedContent(paginator: model.paginator, emptyTitle: "Похоже, нет ни одного канала") { source in
                    let channel = actions.channel(source)
                    HStack(spacing: 8) {
                        NavigationLink(value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: model.viewer)) {
                            ProfileChannelRow(channel: channel)
                        }.buttonStyle(.plain)
                        if channel.isSubscribed == true {
                            if channel.isBlog == true {
                                NavigationLink(value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: model.viewer)) {
                                    Image(systemName: "checkmark").frame(width: 44, height: 44)
                                }.accessibilityLabel("Открыть профиль автора")
                            } else {
                                Button { unsubscribeTarget = channel } label: { Image(systemName: "checkmark").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Отписаться")
                            }
                        } else {
                            FeedSubscribeButton(channel: channel, actions: actions)
                        }
                    }
                    .disabled(actions.pendingChannels.contains(channel.id))
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.reload() }
        .task(id: ObjectIdentifier(model.paginator)) { if model.hasCurrentViewer { await model.paginator.loadFirstPageIfNeeded() } }
        .onChange(of: actions.membershipRevision) { _, _ in
            if observesMembershipChanges { Task { await model.reload() } }
        }
        .confirmationDialog("Отписаться?", isPresented: Binding(get: { unsubscribeTarget != nil }, set: { if !$0 { unsubscribeTarget = nil } }), titleVisibility: .visible) {
            if let channel = unsubscribeTarget {
                Button("Отписаться") { Task { _ = await actions.subscribe(channel, enabled: false); unsubscribeTarget = nil } }
            }
            Button("Отмена", role: .cancel) { unsubscribeTarget = nil }
        }
    }
}

/// Blog subscription has a social effect in the original app. Name that effect
/// before sending the request instead of disguising it as a channel-only write.
@MainActor
struct FeedSubscribeButton: View {
    let channel: Channel
    let actions: FeedActionsModel
    /// The outlined square plus of the beta instead of the text button.
    var compact = false
    @State private var confirmsBlogRequest = false

    private var subscribe: some View {
        Button {
            if channel.isBlog == true { confirmsBlogRequest = true }
            else { Task { _ = await actions.subscribe(channel, enabled: true) } }
        } label: {
            if compact {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary, lineWidth: 2))
                    .contentShape(Rectangle())
            } else {
                Text("Подписаться")
            }
        }
    }

    var body: some View {
        Group {
            if compact { subscribe.buttonStyle(.plain) }
            else { subscribe.font(.ax(.caption, .medium)).buttonStyle(.bordered) }
        }
        .accessibilityLabel("Подписаться")
        .disabled(!actions.hasCurrentViewer || actions.pendingChannels.contains(channel.id) || channel.isDeleted == true)
        .confirmationDialog("Подписаться на блог?", isPresented: $confirmsBlogRequest, titleVisibility: .visible) {
            Button("Отправить заявку") { Task { _ = await actions.subscribe(channel, enabled: true) } }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Автору будет отправлена заявка в друзья, как в Anixart. Это не подписка на обычный канал.") }
    }
}

@MainActor
struct FeedChannelListView: View {
    @Environment(AppEnvironment.self) private var env
    let kind: FeedChannelListModel.Kind
    let viewer: ProfileViewerKey
    let actions: FeedActionsModel
    @State private var model: FeedChannelListModel?

    var body: some View {
        Group {
            if viewer != env.session.viewerKey { ProfileViewerNotice(viewer: viewer) }
            else if kind.requiresAccount, viewer.account == nil { SignInPromptView(message: "Подписки и управляемые каналы привязаны к аккаунту.") }
            else if let model { FeedChannelListContent(model: model, actions: actions) }
            else { ProgressView() }
        }
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard viewer == env.session.viewerKey else { return }
            if model == nil { model = FeedChannelListModel(kind: kind, session: env.session) }
        }
    }
}

/// The empty «Моя лента» suggestion list: one channel per row with the avatar, the
/// name with its verified seal, the subscriber count and an outlined plus.
@MainActor
struct FeedChannelRows: View {
    let channels: [Channel]
    let viewer: ProfileViewerKey
    let actions: FeedActionsModel

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(channels) { source in
                let channel = actions.channel(source)
                HStack(spacing: 14) {
                    NavigationLink(value: FeedRouteContext(route: FeedChannelNavigation.route(for: channel), viewer: viewer)) {
                        HStack(spacing: 14) {
                            Avatar(url: AnixartURL.image(channel.avatar), size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(channel.title ?? "Канал").font(.ax(.title3)).lineLimit(1)
                                    if channel.isVerified == true {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.newBadge)
                                    }
                                }
                                Text(Plural.subscribers(channel.subscriberCount ?? 0))
                                    .font(.ax(.body)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if channel.isSubscribed == true {
                        Text(actions.blogRequestsSent.contains(channel.id) ? "Заявка отправлена" : "Вы подписаны")
                            .font(.ax(.caption)).foregroundStyle(.secondary)
                    } else {
                        FeedSubscribeButton(channel: channel, actions: actions, compact: true)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
        }
    }
}
