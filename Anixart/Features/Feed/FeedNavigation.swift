import SwiftUI
import AnixartKit

enum FeedRoute: Hashable {
    case article(Article)
    case articleID(Int)
    case channel(Channel)
    case profile(Int)
    case comments(Int)
    case voters(Int)
    case reposts(Int)
    case channelSearch(String, isBlog: Bool)
    case subscriptions
}

/// Navigation values retain the original viewer even if the root model changes
/// before SwiftUI finishes dismissing an older navigation stack.
struct FeedRouteContext: Hashable {
    let route: FeedRoute
    let viewer: ProfileViewerKey

    func hash(into hasher: inout Hasher) {
        hasher.combine(route)
        hasher.combine(viewer.revision)
        hasher.combine(viewer.account?.profileID)
        hasher.combine(viewer.account?.revision)
    }
}

@MainActor
struct FeedDestinationView: View {
    @Environment(AppEnvironment.self) private var env
    let context: FeedRouteContext
    let actions: FeedActionsModel

    var body: some View {
        Group {
            if context.viewer != env.session.viewerKey || actions.viewer != context.viewer {
                ProfileViewerNotice(viewer: context.viewer)
            } else {
                destination
            }
        }
        .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var destination: some View {
        switch context.route {
        case .article(let article): ProfileArticleView(articleID: article.id, preloaded: article, viewer: context.viewer)
        case .articleID(let id): ProfileArticleView(articleID: id, viewer: context.viewer)
        case .channel(let channel): ProfileChannelView(channelID: channel.id, preloaded: channel, viewer: context.viewer)
        case .profile(let id): ProfileView(profileID: id, viewer: context.viewer)
        case .comments(let id):
            ProfileCommentsAtLocationView(location: .init(category: .articles, parentID: id), viewer: context.viewer)
        case .voters(let id): ProfileVotersView(source: .article(id), viewer: context.viewer)
        case .reposts(let id): ProfileArticleRepostsView(articleID: id, viewer: context.viewer)
        case .channelSearch(let query, let isBlog):
            FeedChannelListView(kind: .search(query: query, isBlog: isBlog), viewer: context.viewer, actions: actions)
        case .subscriptions:
            FeedChannelListView(kind: .subscriptions, viewer: context.viewer, actions: actions)
        }
    }
}

enum FeedChannelNavigation {
    static func route(for channel: Channel) -> FeedRoute {
        if channel.isBlog == true, let profileID = channel.blogProfileId, profileID > 0 { return .profile(profileID) }
        return .channel(channel)
    }
}
