import Foundation
import AnixartKit

@MainActor
@Observable
final class ProfileViewModel {
    private(set) var profile: Profile?
    private(set) var coverURL: URL?
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

            async let badges = try? session.sendViewerRequest(ProfileBadgeEndpoints.sections(profileID: profileID), for: viewer)
            async let blog = Self.blog(for: updated, session: session, viewer: viewer)
            async let social = Self.social(for: updated, session: session, viewer: viewer)
            let (badgeResponse, blogResponse, socialResponse) = await (badges, blog, social)
            try Task.checkCancellation()
            guard requestGeneration == generation, session.viewerKey == viewer else { return }

            if let badgeResponse { showcased = badgeResponse.showcased ?? [] }
            if (updated.ratingScore ?? 0) < ProfileEditorRules.minimumCoverReputation {
                coverURL = nil
            } else if let blogResponse {
                coverURL = AnixartURL.image(blogResponse.channel?.cover)
            }
            if let socialResponse {
                var current = updated
                current.vkPage = socialResponse.vkPage
                current.tgPage = socialResponse.tgPage
                current.discordPage = socialResponse.discordPage
                current.ttPage = socialResponse.ttPage
                current.instPage = socialResponse.instPage
                profile = current
            }
        } catch {
            guard requestGeneration == generation, session.viewerKey == viewer,
                  !ProfileRequestFailure.isCancellation(error) else { return }
            errorMessage = Paginator<Release>.message(for: error)
        }
    }

    private static func blog(for profile: Profile, session: SessionController, viewer: ProfileViewerKey) async -> ChannelResponse? {
        guard (profile.ratingScore ?? 0) >= ProfileEditorRules.minimumCoverReputation else { return nil }
        return try? await session.sendViewerRequest(ChannelEndpoints.blog(profileID: profile.id), for: viewer)
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
