import Foundation
import AnixartKit

@MainActor
@Observable
final class ProfileFriendsModel {
    enum Group: CaseIterable, Hashable, Sendable { case incoming, outgoing, friends }
    enum Action: Equatable { case send, accept, hide, cancel, remove }

    let ownerID: Int
    let viewer: ProfileViewerKey
    private let session: SessionController
    private(set) var lists: [Group: Paginator<Profile>] = [:]
    let recommendations = ProfileResource<PageableResponse<Profile>>()
    private(set) var savingIDs = Set<Int>()
    var errorMessage: String?

    init(ownerID: Int, viewer: ProfileViewerKey, session: SessionController) {
        self.ownerID = ownerID
        self.viewer = viewer
        self.session = session
    }

    var hasCurrentViewer: Bool { session.viewerKey == viewer }
    var ownsList: Bool { hasCurrentViewer && viewer.account?.profileID == ownerID }

    func invalidate(for current: ProfileViewerKey) {
        if viewer != current { lists = [:]; recommendations.reset(); errorMessage = nil }
    }

    func load(refresh: Bool = false) async {
        guard hasCurrentViewer else { return }
        let groups: [Group] = ownsList ? [.incoming, .outgoing, .friends] : [.friends]
        for group in groups {
            if lists[group] == nil {
                let session = self.session
                let viewer = self.viewer
                let owner = ownerID
                lists[group] = Paginator { page in
                    switch group {
                    case .friends: return try await session.sendViewerRequest(ProfileEndpoints.friends(of: owner, page: page), for: viewer)
                    case .incoming, .outgoing:
                        guard let account = viewer.account, account.profileID == owner else { throw CancellationError() }
                        return try await session.sendAccountRequest(group == .incoming
                            ? ProfileEndpoints.incomingFriendRequests(page: page)
                            : ProfileEndpoints.outgoingFriendRequests(page: page), for: account)
                    }
                }
            }
        }
        async let friends: Void = loadGroup(.friends, refresh: refresh)
        async let incoming: Void = loadGroup(.incoming, refresh: refresh)
        async let outgoing: Void = loadGroup(.outgoing, refresh: refresh)
        async let suggested: Void = loadRecommendations(refresh: refresh)
        _ = await (friends, incoming, outgoing, suggested)
    }

    private func loadGroup(_ group: Group, refresh: Bool) async {
        guard let list = lists[group] else { return }
        if refresh { await list.reload() } else { await list.loadFirstPageIfNeeded() }
    }

    private func loadRecommendations(refresh: Bool) async {
        // Recommendations are an owner/viewer gate, not a page of someone else's friends.
        guard ownsList, let account = viewer.account,
              refresh || !recommendations.hasAttemptedLoad else { return }
        await recommendations.load { try await session.sendAccountRequest(ProfileEndpoints.friendRecommendations(), for: account) }
    }

    func change(_ profile: Profile, action: Action) async {
        guard ownsList, let account = viewer.account, !savingIDs.contains(profile.id), profile.id != ownerID else { return }
        savingIDs.insert(profile.id)
        errorMessage = nil
        defer { savingIDs.remove(profile.id) }
        do {
            switch action {
            case .send, .accept:
                try await session.sendConfirmedAccountRequest(ProfileEndpoints.sendFriendRequest(to: profile.id), for: account)
            case .hide:
                try await session.sendConfirmedAccountRequest(ProfileEndpoints.hideFriendRequest(profile.id), for: account)
                // Hiding only removes the incoming row; do not rewrite friendStatus.
                lists[.incoming]?.remove(id: profile.id)
            case .cancel, .remove:
                try await session.sendConfirmedAccountRequest(ProfileEndpoints.removeFriend(profile.id), for: account)
            }
            await load(refresh: true)
            await session.refreshProfile(for: account)
        } catch {
            guard hasCurrentViewer, !ProfileRequestFailure.isCancellation(error) else { return }
            if let apiError = error as? AnixartError, case .api(let code, _) = apiError,
               code == 3, action == .send || action == .accept {
                await load(refresh: true)
            } else { errorMessage = ProfileFriendFailure.message(for: error) }
        }
    }
}

enum ProfileFriendFailure {
    static func message(for error: any Error) -> String {
        if let apiError = error as? AnixartError, case .api(let code, _) = apiError {
            switch code {
            case 6, 9: return "Достигнут лимит друзей или заявок вашей учётной записи."
            case 7: return "Пользователь достиг лимита друзей или заявок."
            default: break
            }
        }
        return Paginator<Release>.message(for: error)
    }
}
