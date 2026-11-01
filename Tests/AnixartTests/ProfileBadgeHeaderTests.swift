import Foundation
import SwiftUI
import UIKit
import XCTest
import AnixartKit
@testable import Anixart

/// Synthetic fixtures and reserved .invalid transports only. No phone account,
/// badge writes, screenshots or external artwork are used by these regressions.
final class ProfileBadgeHeaderTests: XCTestCase {
    private func badge(owned: Bool? = nil) throws -> Badge {
        let ownership = owned.map { ",\"is_owned\":\($0)" } ?? ""
        return try profileTestDecode(Badge.self, "{\"id\":7,\"name\":\"Installed\"\(ownership)}")
    }

    private func profile(id: Int = 42) throws -> Profile {
        try profileTestDecode(Profile.self, "{\"id\":\(id),\"badge_id\":7,\"badge_name\":\"Installed\",\"badge_type\":0}")
    }

    func testInstalledHeaderChangeIsNavigationEvenWithoutOwnershipMetadata() throws {
        let viewer = ProfileAccountKey(profileID: 42, revision: 1).viewerKey
        for owned in [nil, false, true] as [Bool?] {
            let action = ProfileBadgeDetailEntry.installedHeader.primaryAction(
                badge: try badge(owned: owned), isSelected: true, profileID: 42, viewer: viewer, currentViewer: viewer)
            XCTAssertEqual(action, .change)
            XCTAssertEqual(action?.title, "Сменить значок")
        }
    }

    func testCollectionAndSelectionDetailsKeepExplicitSelectAndRemoveSemantics() throws {
        let viewer = ProfileAccountKey(profileID: 42, revision: 1).viewerKey
        let owned = try badge(owned: true)
        let remove = ProfileBadgeDetailEntry.collection.primaryAction(
            badge: owned, isSelected: true, profileID: 42, viewer: viewer, currentViewer: viewer)
        XCTAssertEqual(remove, .remove)
        XCTAssertEqual(remove?.title, "Снять")
        let select = ProfileBadgeDetailEntry.collection.primaryAction(
            badge: owned, isSelected: false, profileID: 42, viewer: viewer, currentViewer: viewer)
        XCTAssertEqual(select, .select)
        XCTAssertEqual(select?.title, "Установить")
        for ownership in [nil, false] as [Bool?] {
            XCTAssertNil(ProfileBadgeDetailEntry.collection.primaryAction(
                badge: try badge(owned: ownership), isSelected: true, profileID: 42, viewer: viewer, currentViewer: viewer))
        }
    }

    func testForeignGuestAndStaleViewerDetailsHaveNoPrimaryAccountAction() throws {
        let viewer = ProfileAccountKey(profileID: 42, revision: 1).viewerKey
        let replacement = ProfileAccountKey(profileID: 42, revision: 2).viewerKey
        let guest = ProfileViewerKey(account: nil, revision: 0)
        let owned = try badge(owned: true)
        for entry in [ProfileBadgeDetailEntry.installedHeader, .collection] {
            XCTAssertNil(entry.primaryAction(badge: owned, isSelected: true, profileID: 71,
                                             viewer: viewer, currentViewer: viewer))
            XCTAssertNil(entry.primaryAction(badge: owned, isSelected: true, profileID: 42,
                                             viewer: guest, currentViewer: guest))
            XCTAssertNil(entry.primaryAction(badge: owned, isSelected: true, profileID: 42,
                                             viewer: viewer, currentViewer: replacement))
            XCTAssertNil(entry.primaryAction(badge: owned, isSelected: true, profileID: 42,
                                             viewer: nil, currentViewer: viewer))
        }
    }

    @MainActor
    func testHeaderPresentationRequiresAnInstalledBadgeAndTheCurrentViewer() throws {
        let viewer = ProfileAccountKey(profileID: 42, revision: 2).viewerKey
        let stale = ProfileAccountKey(profileID: 42, revision: 1).viewerKey
        let model = ProfileInstalledBadgeModel()
        model.open(profile: try profileTestDecode(Profile.self, #"{"id":42}"#), viewer: viewer, currentViewer: viewer)
        XCTAssertNil(model.detail)
        model.open(profile: try profile(), viewer: nil, currentViewer: viewer)
        XCTAssertNil(model.detail)
        model.open(profile: try profile(), viewer: stale, currentViewer: viewer)
        XCTAssertNil(model.detail)
        model.open(profile: try profile(), viewer: viewer, currentViewer: viewer)
        let presentation = try XCTUnwrap(model.detail)
        XCTAssertEqual(presentation.profileID, 42)
        XCTAssertEqual(presentation.badge.id, 7)
        XCTAssertNil(presentation.badge.isOwned)
        let sheet = model.sheet(for: presentation)
        XCTAssertEqual(sheet.entry, .installedHeader)
        XCTAssertEqual(sheet.viewer, viewer)
        XCTAssertTrue(sheet.model === model.badges)
        model.invalidate(for: viewer)
        XCTAssertNotNil(model.detail, "The unchanged session must not dismiss the sheet")
    }

    @MainActor
    func testForeignHeaderOpensDetailsButDoesNotGainOwnerNavigation() throws {
        let viewer = ProfileAccountKey(profileID: 42, revision: 1).viewerKey
        let model = ProfileInstalledBadgeModel()
        model.open(profile: try profile(id: 71), viewer: viewer, currentViewer: viewer)
        let presentation = try XCTUnwrap(model.detail)
        let sheet = model.sheet(for: presentation)
        XCTAssertEqual(sheet.profileID, 71)
        XCTAssertEqual(sheet.entry, .installedHeader)
        XCTAssertNil(sheet.entry.primaryAction(badge: sheet.badge, isSelected: true,
                                               profileID: sheet.profileID, viewer: sheet.viewer, currentViewer: viewer))
    }

    @MainActor
    func testReplacementSessionDismissesHeaderDetailsAndCannotPublishALateRead() async throws {
        for newID in [42, 43] {
            let suite = "ProfileBadgeHeaderTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let rig = ProfileTestRig()
            try await rig.signIn(token: "previous")
            let viewer = rig.session.viewerKey
            let model = ProfileInstalledBadgeModel(defaults: defaults)
            model.open(profile: try profile(), viewer: viewer, currentViewer: viewer)
            let held = rig.api.hold("/profile/42/badge/list")
            defer { held.respond("{}", status: 500) }
            let read = Task { await model.badges.load(profileID: 42, session: rig.session, viewer: viewer) }
            defer { read.cancel() }
            await fulfillment(of: [held.arrived], timeout: 5)
            try await rig.signIn(profileID: newID, token: "current")
            model.invalidate(for: rig.session.viewerKey)
            XCTAssertNil(model.detail)
            held.respond(#"{"code":0,"profile":{"id":42,"badge_id":7},"showcased":[],"recent":[],"sections":[]}"#)
            await read.value
            XCTAssertNil(model.badges.resource.value)
            XCTAssertNil(model.badges.resource.errorMessage)
            XCTAssertFalse(model.badges.canEdit)
        }
    }

    @MainActor
    func testOpeningHeaderDetailsAndTheSelectorOnlyReadsBadgeSections() async throws {
        let suite = "ProfileBadgeHeaderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let rig = ProfileTestRig()
        try await rig.signIn()
        let viewer = rig.session.viewerKey
        let model = ProfileInstalledBadgeModel(defaults: defaults)
        let before = rig.api.requests.count
        model.open(profile: try profile(), viewer: viewer, currentViewer: viewer)
        let presentation = try XCTUnwrap(model.detail)
        let sheet = model.sheet(for: presentation)
        XCTAssertFalse(model.badges.canEdit, "Opening the selector must not need mutation eligibility")
        XCTAssertEqual(sheet.entry.primaryAction(badge: sheet.badge, isSelected: true,
                                                 profileID: sheet.profileID, viewer: sheet.viewer, currentViewer: viewer), .change)
        let selector = ProfileBadgesView(profileID: sheet.profileID, selecting: true, viewer: sheet.viewer)
        XCTAssertTrue(selector.selecting)
        XCTAssertEqual(selector.profileID, 42)
        XCTAssertEqual(rig.api.requests.count, before)
        rig.api.enqueue("/profile/42/badge/list", json:
            #"{"code":0,"profile":{"id":42,"badge_id":7,"badge_name":"Installed"},"showcased":[],"recent":[],"sections":[]}"#)
        await model.badges.load(profileID: sheet.profileID, session: rig.session, viewer: viewer)
        let reads = Array(rig.api.requests.dropFirst(before))
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first?.httpMethod, "GET")
        XCTAssertEqual(reads.first?.url?.path, "/profile/42/badge/list")
        XCTAssertTrue(reads.allSatisfy { $0.url?.path.contains("/preference/") == false })
        XCTAssertNil(model.badges.errorMessage)
    }

    @MainActor
    func testCompactAndRegularTilesExposeOnlyNonemptyAwardReleaseSubtitles() throws {
        let awarded = try profileTestDecode(Badge.self,
            #"{"id":7,"name":"Награда","award":{"release_title":" Связанный релиз "}}"#)
        for compact in [true, false] {
            XCTAssertEqual(ProfileBadgeTile(badge: awarded, compact: compact).releaseSubtitle, "Связанный релиз")
            for json in [#"{"id":7}"#, #"{"id":7,"award":{}}"#,
                         #"{"id":7,"award":{"release_title":""}}"#,
                         #"{"id":7,"award":{"release_title":" \n "}}"#] {
                let empty = try profileTestDecode(Badge.self, json)
                XCTAssertNil(ProfileBadgeTile(badge: empty, compact: compact).releaseSubtitle)
            }
        }
    }

    @MainActor
    func testCompactSubtitleRendersAndFourColumnGridKeepsDynamicTypeSizing() throws {
        let plain = try profileTestDecode(Badge.self, #"{"id":7,"name":"Награда"}"#)
        let awarded = try profileTestDecode(Badge.self,
            #"{"id":7,"name":"Награда","award":{"release_title":"Связанный релиз"}}"#)
        @MainActor func tileImage(_ badge: Badge) throws -> UIImage {
            let renderer = ImageRenderer(content: ProfileBadgeTile(badge: badge, compact: true)
                .frame(width: 72).environment(\.dynamicTypeSize, .medium))
            renderer.scale = 1
            return try XCTUnwrap(renderer.uiImage)
        }
        let awardedImage = try tileImage(awarded)
        let plainImage = try tileImage(plain)
        XCTAssertGreaterThan(awardedImage.size.height, plainImage.size.height,
                             "The compact subtitle must be part of the rendered layout, not just its data")
        XCTAssertEqual(ProfileBadgeGridLayout.columns.count, 4)
        let badges = (1...4).map { id in var badge = awarded; badge.id = id; return badge }
        @MainActor func gridImage(_ dynamicType: DynamicTypeSize) throws -> UIImage {
            let grid = LazyVGrid(columns: ProfileBadgeGridLayout.columns, spacing: 20) {
                ForEach(badges) { ProfileBadgeTile(badge: $0, compact: true) }
            }
            .frame(width: 320).environment(\.dynamicTypeSize, dynamicType)
            let renderer = ImageRenderer(content: grid)
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
            return try XCTUnwrap(renderer.uiImage)
        }
        let normal = try gridImage(.medium)
        let large = try gridImage(.accessibility3)
        XCTAssertEqual(normal.size.width, 320, accuracy: 0.5)
        XCTAssertEqual(large.size.width, 320, accuracy: 0.5)
        XCTAssertGreaterThan(large.size.height, normal.size.height)
    }
}
