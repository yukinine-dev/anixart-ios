import Foundation
import AnixartKit

@MainActor
@Observable
final class ProfileViewModel {
    private(set) var profile: Profile?
    private(set) var coverURL: URL?
    private(set) var blog: Channel?
    private(set) var blogErrorMessage: String?
    private(set) var badgeErrorMessage: String?
    private(set) var showcased: [Badge] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var viewerKey: ProfileViewerKey?
    var viewerSessionRevision: Int? { viewerKey?.revision }
    var viewerAccount: ProfileAccountKey? { viewerKey?.account }
    var section: ProfileSection = .statistics
    private var generation = 0
    private var loadingViewer: ProfileViewerKey?

    func invalidate(for current: ProfileViewerKey) {
        if let viewer = loadingViewer ?? viewerKey, viewer != current { reset() }
    }

    func reset() {
        generation += 1
        profile = nil
        coverURL = nil
        blog = nil
        blogErrorMessage = nil
        badgeErrorMessage = nil
        showcased = []
        viewerKey = nil
        loadingViewer = nil
        errorMessage = nil
        isLoading = false
    }

    func adopt(_ updated: Profile) {
        if profile == nil || profile?.id != updated.id || profile?.pinnedSectionId != updated.pinnedSectionId {
            section = ProfileSection(rawValue: updated.pinnedSectionId ?? 0) ?? .statistics
        }
        profile = updated
        if !updated.visibleSections.contains(section) {
            section = updated.visibleSections.first ?? .badges
        }
    }

    func applyFriendStatus(_ status: FriendStatusCode?, profileID: Int) {
        guard var current = profile, current.id == profileID else { return }
        current.friendStatus = status
        adopt(current)
    }

    func applyBlockState(_ blocked: Bool, profileID: Int) {
        guard var current = profile, current.id == profileID else { return }
        current.isBlocked = blocked
        if blocked { current.friendStatus = nil }
        adopt(current)
    }

    /// Reload the separate cover/showcase resources even when the profile JSON
    /// hasn't changed. A newer refresh wins over an older or cancelled request.
    func load(profileID: Int, session: SessionController, viewer expectedViewer: ProfileViewerKey? = nil) async {
        let viewer = expectedViewer ?? session.viewerKey
        guard viewer == session.viewerKey else {
            invalidate(for: session.viewerKey)
            return
        }
        generation += 1
        let requestGeneration = generation
        loadingViewer = viewer
        isLoading = true
        errorMessage = nil
        if profile?.id != profileID || viewerKey != viewer {
            profile = nil
            coverURL = nil
            blog = nil
            blogErrorMessage = nil
            badgeErrorMessage = nil
            showcased = []
            viewerKey = nil
        }
        defer {
            if requestGeneration == generation { isLoading = false; loadingViewer = nil }
        }

        do {
            let response = try await session.sendViewerRequest(ProfileEndpoints.profile(id: profileID), for: viewer)
            try Task.checkCancellation()
            guard requestGeneration == generation, session.viewerKey == viewer else { return }
            guard let updated = response.profile, updated.id == profileID else {
                throw AnixartError.decoding(message: "Ответ не содержит профиль", path: "profile/\(profileID)")
            }
            adopt(updated)
            viewerKey = viewer

            async let badges = Self.badges(for: profileID, session: session, viewer: viewer)
            async let blog = Self.blog(for: updated, session: session, viewer: viewer)
            async let social = Self.social(for: updated, session: session, viewer: viewer)
            let (badgesResult, blogResponse, socialResponse) = await (badges, blog, social)
            try Task.checkCancellation()
            guard requestGeneration == generation, session.viewerKey == viewer else { return }

            var current = updated
            switch badgesResult {
            case .success(let badgeResponse):
                badgeErrorMessage = nil
                current.badgesPreview = updated.badgesPreview?.map { ProfileBadgePresentation.resolved($0, in: badgeResponse) }
                if let selected = current.selectedBadge {
                    current.badge = ProfileBadgePresentation.resolved(selected, in: badgeResponse)
                }
                showcased = ProfileBadgePresentation.unique(badgeResponse.showcased
                    ?? current.badgesPreview?.filter { $0.isShowcased == true } ?? [])
                    .map { ProfileBadgePresentation.resolved($0, in: badgeResponse) }
            case .failure(let error):
                showcased = ProfileBadgePresentation.unique(current.badgesPreview?.filter { $0.isShowcased == true } ?? [])
                if !ProfileRequestFailure.isCancellation(error) {
                    badgeErrorMessage = Paginator<Release>.message(for: error)
                }
            }
            switch blogResponse {
            case .success(let response):
                blogErrorMessage = nil
                self.blog = response.channel
                coverURL = AnixartURL.image(response.channel?.cover)
            case .failure(let error):
                // A failed read is not an empty blog. Keep an existing cover.
                if let apiError = error as? AnixartError, case .api(let code, _) = apiError,
                   code == AnixartStatus.banned || code == AnixartStatus.permBanned {
                    self.blog = nil
                    coverURL = nil
                }
                if !ProfileRequestFailure.isCancellation(error) {
                    blogErrorMessage = Paginator<Release>.message(for: error)
                }
            }
            if let socialResponse {
                current.vkPage = socialResponse.vkPage
                current.tgPage = socialResponse.tgPage
                current.discordPage = socialResponse.discordPage
                current.ttPage = socialResponse.ttPage
                current.instPage = socialResponse.instPage
            }
            profile = current
        } catch {
            guard requestGeneration == generation, session.viewerKey == viewer,
                  !ProfileRequestFailure.isCancellation(error) else { return }
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    private static func badges(for profileID: Int, session: SessionController, viewer: ProfileViewerKey) async -> Result<ProfileBadgeSectionsResponse, Error> {
        do {
            let response = try await session.sendViewerRequest(ProfileBadgeEndpoints.sections(profileID: profileID), for: viewer)
            guard response.profile == nil || response.profile?.id == profileID else {
                throw AnixartError.decoding(message: "Ответ содержит значки другого профиля", path: "profile/\(profileID)/badge/list")
            }
            guard response.sections != nil || response.showcased != nil || response.recent != nil || response.totalCount == 0 else {
                throw AnixartError.decoding(message: "Ответ не содержит список значков", path: "profile/\(profileID)/badge/list")
            }
            return .success(response)
        } catch { return .failure(error) }
    }

    private static func blog(for profile: Profile, session: SessionController, viewer: ProfileViewerKey) async -> Result<ChannelResponse, Error> {
        do {
            let response = try await session.sendViewerRequest(ChannelEndpoints.blog(profileID: profile.id), for: viewer)
            if let owner = response.channel?.blogProfileId, owner != profile.id {
                throw AnixartError.decoding(message: "Ответ содержит блог другого профиля", path: "channel/blog/\(profile.id)")
            }
            return .success(response)
        } catch { return .failure(error) }
    }

    private static func social(for profile: Profile, session: SessionController, viewer: ProfileViewerKey) async -> ProfileSocialResponse? {
        guard profile.isSocialHidden != true else { return nil }
        return try? await session.sendViewerRequest(ProfileEndpoints.social(id: profile.id), for: viewer)
    }
}

struct ProfileReloadKey: Equatable {
    let profileID: Int
    let profileRevision: Int
    let sessionRevision: Int
    let viewerAccount: ProfileAccountKey?
}
