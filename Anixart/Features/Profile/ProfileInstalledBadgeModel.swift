import Foundation
import AnixartKit

/// The header opens details for the exact viewer that loaded the profile. Its
/// installed-badge context navigates to selection; opening it never edits a badge.
@MainActor
@Observable
final class ProfileInstalledBadgeModel {
    struct Presentation: Identifiable {
        let profileID: Int
        let badge: Badge
        let viewer: ProfileViewerKey
        var id: Int { badge.id }
    }

    var detail: Presentation?
    let badges: ProfileBadgesModel
    private var presentedViewer: ProfileViewerKey?

    init(defaults: UserDefaults = .standard) {
        badges = ProfileBadgesModel(defaults: defaults)
    }

    func open(profile: Profile, viewer: ProfileViewerKey?, currentViewer: ProfileViewerKey) {
        guard profile.id > 0, let viewer, viewer == currentViewer, let badge = profile.selectedBadge else { return }
        reset()
        presentedViewer = viewer
        detail = Presentation(profileID: profile.id, badge: badge, viewer: viewer)
    }

    func invalidate(for currentViewer: ProfileViewerKey) {
        if let presentedViewer, presentedViewer != currentViewer { reset() }
    }

    func sheet(for presentation: Presentation) -> ProfileBadgeDetailSheet {
        ProfileBadgeDetailSheet(badge: presentation.badge, profileID: presentation.profileID,
                                model: badges, entry: .installedHeader, viewer: presentation.viewer)
    }

    private func reset() {
        detail = nil
        presentedViewer = nil
        badges.resource.reset()
        badges.errorMessage = nil
    }
}
