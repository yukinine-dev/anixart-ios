import Foundation
import XCTest
import AnixartKit
@testable import Anixart

private struct ProfileTestItem: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    var name: String?
}

final class ProfileStateTests: XCTestCase {
    @MainActor
    func testAdoptedResourceSupersedesDelayedLoad() async {
        let resource = ProfileResource<ProfileTestItem>()
        let gate = ProfileTestGate()
        defer { gate.release() }
        let old = Task { await resource.load { await gate.wait(); return ProfileTestItem(id: 1, name: "old") } }
        defer { old.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        resource.adopt(ProfileTestItem(id: 1, name: "saved"))
        gate.release()
        await old.value
        XCTAssertEqual(resource.value?.name, "saved")
        XCTAssertFalse(resource.isLoading)
        XCTAssertTrue(resource.hasAttemptedLoad)
        XCTAssertNil(resource.errorMessage)
    }

    @MainActor
    func testOldFailureCannotStopOrFailANewerResourceLoad() async {
        let resource = ProfileResource<ProfileTestItem>()
        let oldGate = ProfileTestGate()
        let newGate = ProfileTestGate()
        defer { oldGate.release(); newGate.release() }
        let old = Task { await resource.load { await oldGate.wait(); throw URLError(.notConnectedToInternet) } }
        defer { old.cancel() }
        await fulfillment(of: [oldGate.entered], timeout: 5)
        let current = Task { await resource.load { await newGate.wait(); return ProfileTestItem(id: 2) } }
        defer { current.cancel() }
        await fulfillment(of: [newGate.entered], timeout: 5)
        oldGate.release()
        await old.value
        XCTAssertTrue(resource.isLoading)
        XCTAssertNil(resource.errorMessage)
        newGate.release()
        await current.value
        XCTAssertEqual(resource.value?.id, 2)
    }

    @MainActor
    func testCancelledResourceLoadKeepsPreviousValueWithoutError() async {
        let resource = ProfileResource<ProfileTestItem>()
        resource.adopt(ProfileTestItem(id: 1))
        let gate = ProfileTestGate()
        defer { gate.release() }
        let load = Task { await resource.load { await gate.wait(); return ProfileTestItem(id: 2) } }
        defer { load.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        load.cancel()
        gate.release()
        await load.value
        XCTAssertEqual(resource.value?.id, 1)
        XCTAssertNil(resource.errorMessage)
        XCTAssertFalse(resource.isLoading)
    }

    @MainActor
    func testResourceResetInvalidatesPendingResponse() async {
        let resource = ProfileResource<ProfileTestItem>()
        let gate = ProfileTestGate()
        defer { gate.release() }
        let load = Task { await resource.load { await gate.wait(); return ProfileTestItem(id: 1) } }
        defer { load.cancel() }
        await fulfillment(of: [gate.entered], timeout: 5)
        resource.reset()
        gate.release()
        await load.value
        XCTAssertNil(resource.value)
        XCTAssertFalse(resource.hasAttemptedLoad)
        XCTAssertFalse(resource.isLoading)
    }

    @MainActor
    private func paginator(_ rig: ProfileTestRig) -> Paginator<ProfileTestItem> {
        Paginator { page in
            try await rig.client.send(Endpoint<PageableResponse<ProfileTestItem>>(path: "items/\(page)", auth: .none))
        }
    }

    private func page(_ ids: [Int], index: Int = 0, pages: Int = 2, total: Int? = nil) -> String {
        let items = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
        return "{\"code\":0,\"content\":[\(items)],\"current_page\":\(index),\"total_page_count\":\(pages),\"total_count\":\(total ?? ids.count)}"
    }

    @MainActor
    func testPaginatorDeduplicatesWithinAndAcrossPages() async {
        let rig = ProfileTestRig()
        rig.api.enqueue("/items/0", json: page([1, 1, 2], total: 3))
        rig.api.enqueue("/items/1", json: page([2, 3, 3], index: 1, total: 3))
        let paginator = paginator(rig)
        await paginator.loadFirstPageIfNeeded()
        await paginator.loadNextPage()
        XCTAssertEqual(paginator.items.map(\.id), [1, 2, 3])
        XCTAssertEqual(paginator.totalCount, 3)
        XCTAssertFalse(paginator.hasMore)
        await paginator.loadNextPage()
        XCTAssertEqual(rig.api.requests(to: "/items/1").count, 1)
    }

    @MainActor
    func testPaginatorRetriesFailedNextPageWithoutReloadingFirstPage() async {
        let rig = ProfileTestRig()
        rig.api.enqueue("/items/0", json: page([1], total: 2))
        rig.api.enqueue("/items/1", json: #"{"code":2}"#)
        rig.api.enqueue("/items/1", json: page([2], index: 1, total: 2))
        let paginator = paginator(rig)
        await paginator.loadFirstPageIfNeeded()
        await paginator.loadNextPage()
        XCTAssertEqual(paginator.failedPage, 1)
        XCTAssertEqual(paginator.items.map(\.id), [1])
        await paginator.retry()
        XCTAssertEqual(paginator.items.map(\.id), [1, 2])
        XCTAssertNil(paginator.failedPage)
        XCTAssertNil(paginator.errorMessage)
        XCTAssertEqual(rig.api.requests(to: "/items/0").count, 1)
        XCTAssertEqual(rig.api.requests(to: "/items/1").count, 2)
    }

    @MainActor
    func testPaginatorRetriesFailedFirstPage() async {
        let rig = ProfileTestRig()
        rig.api.enqueue("/items/0", json: #"{"code":2}"#)
        rig.api.enqueue("/items/0", json: page([1], pages: 1))
        let paginator = paginator(rig)
        await paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(paginator.failedPage, 0)
        await paginator.retry()
        XCTAssertEqual(paginator.items.map(\.id), [1])
        XCTAssertEqual(paginator.state, .idle)
    }

    @MainActor
    func testRemovalRebasesFromPageZeroAndInvalidatesPendingNextPage() async {
        let rig = ProfileTestRig()
        rig.api.enqueue("/items/0", json: page([1, 2], total: 4))
        let held = rig.api.hold("/items/1")
        defer { held.respond("{}", status: 500) }
        let paginator = paginator(rig)
        await paginator.loadFirstPageIfNeeded()
        let oldNext = Task { await paginator.loadNextPage() }
        defer { oldNext.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/items/0", json: page([2, 3], total: 3))
        await paginator.removeAndReload(id: 1)
        held.respond(page([3, 4], index: 1, total: 4))
        await oldNext.value
        XCTAssertEqual(paginator.items.map(\.id), [2, 3])
        XCTAssertEqual(paginator.totalCount, 3)
        rig.api.enqueue("/items/1", json: page([4], index: 1, total: 3))
        await paginator.loadNextPage()
        XCTAssertEqual(paginator.items.map(\.id), [2, 3, 4])
    }

    @MainActor
    func testRemovingMissingIDDoesNotDecreaseCount() async {
        let rig = ProfileTestRig()
        rig.api.enqueue("/items/0", json: page([1, 2], pages: 1, total: 2))
        let paginator = paginator(rig)
        await paginator.loadFirstPageIfNeeded()
        paginator.remove(id: 99)
        XCTAssertEqual(paginator.totalCount, 2)
        paginator.remove(id: 1)
        paginator.remove(id: 1)
        XCTAssertEqual(paginator.totalCount, 1)
        XCTAssertEqual(paginator.items.map(\.id), [2])
    }

    @MainActor
    func testCancelledPaginatorFirstPageCanBeLoadedAgain() async {
        let rig = ProfileTestRig()
        let held = rig.api.hold("/items/0")
        defer { held.respond("{}", status: 500) }
        let paginator = paginator(rig)
        let load = Task { await paginator.loadFirstPageIfNeeded() }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        load.cancel()
        await load.value
        XCTAssertEqual(paginator.state, .idle)
        XCTAssertNil(paginator.errorMessage)
        XCTAssertNil(paginator.failedPage)
        rig.api.enqueue("/items/0", json: page([1], pages: 1))
        await paginator.loadFirstPageIfNeeded()
        XCTAssertEqual(paginator.items.map(\.id), [1])
    }

    @MainActor
    func testProfileSectionSelectionIsPreservedUnlessPinnedSectionChanges() throws {
        let model = ProfileViewModel()
        let first = try profileTestDecode(Profile.self, #"{"id":42,"pinned_section_id":5}"#)
        model.adopt(first)
        XCTAssertEqual(model.section, .badges)
        model.section = .comments
        model.adopt(first)
        XCTAssertEqual(model.section, .comments)
        model.adopt(try profileTestDecode(Profile.self, #"{"id":42,"pinned_section_id":2}"#))
        XCTAssertEqual(model.section, .collections)
        model.adopt(try profileTestDecode(Profile.self, #"{"id":43,"pinned_section_id":99}"#))
        XCTAssertEqual(model.section, .statistics)
    }

    @MainActor
    func testProfileRefreshReloadsCoverAndShowcaseEvenWhenProfileIsEqual() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = ProfileViewModel()
        for (id, cover) in [(1, "first"), (2, "second")] {
            rig.api.enqueue("/profile/71", json: #"{"code":0,"profile":{"id":71,"rating_score":3,"is_social_hidden":true}}"#)
            rig.api.enqueue("/profile/71/badge/list", json: "{\"code\":0,\"showcased\":[{\"id\":\(id)}]}")
            rig.api.enqueue("/channel/blog/71", json: "{\"code\":0,\"channel\":{\"id\":1,\"cover\":\"https://example.invalid/\(cover).jpg\"}}")
            await model.load(profileID: 71, session: rig.session)
            XCTAssertEqual(model.showcased.map(\.id), [id])
            XCTAssertEqual(model.coverURL?.lastPathComponent, "\(cover).jpg")
        }
        XCTAssertEqual(rig.api.requests(to: "/channel/blog/71").count, 2)
        XCTAssertTrue(rig.api.requests(to: "/profile/social/71").isEmpty)
    }

    @MainActor
    func testProfileBelowCreationReputationStillLoadsExistingBlogAndCover() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        rig.api.enqueue("/profile/71", json: #"{"code":0,"profile":{"id":71,"rating_score":2,"is_social_hidden":true}}"#)
        rig.api.enqueue("/profile/71/badge/list", json: #"{"code":0,"showcased":[]}"#)
        rig.api.enqueue("/channel/blog/71", json: #"{"code":0,"channel":{"id":1,"blog_profile_id":71,"cover":"https://example.invalid/existing.jpg"}}"#)
        let model = ProfileViewModel()
        await model.load(profileID: 71, session: rig.session)
        XCTAssertEqual(model.coverURL?.lastPathComponent, "existing.jpg")
        XCTAssertEqual(model.blog?.id, 1)
        XCTAssertEqual(rig.api.requests(to: "/channel/blog/71").count, 1)
    }

    @MainActor
    func testRecentActivityKeepsOriginalGuestViewerAfterSignIn() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let guest = rig.session.viewerKey
        let profile = try profileTestDecode(Profile.self, #"{"id":71,"history":[{"id":72,"is_favorite":false}]}"#)
        let section = ProfileActivitySection(profile: profile, viewer: guest)
        try await rig.signIn()
        XCTAssertEqual(section.viewer, guest)
        let release = try XCTUnwrap(section.profile.history?.first)
        let detail = ReleaseDetailViewModel(releaseID: release.id, preloaded: release,
                                           session: rig.session, viewer: section.viewer)
        XCTAssertEqual(detail.viewer, guest)
        XCTAssertFalse(detail.hasCurrentViewer)
        let requests = rig.api.requests.count
        await detail.load()
        await detail.toggleFavorite()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testRecentActivityKeepsOriginalViewerAfterAnotherLoginToSameProfile() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let viewer = rig.session.viewerKey
        let profile = try profileTestDecode(Profile.self, #"{"id":71,"history":[{"id":72,"is_favorite":false}]}"#)
        let section = ProfileActivitySection(profile: profile, viewer: viewer)
        try await rig.signIn(token: "second")
        XCTAssertEqual(section.viewer, viewer)
        let release = try XCTUnwrap(section.profile.history?.first)
        let detail = ReleaseDetailViewModel(releaseID: release.id, preloaded: release,
                                           session: rig.session, viewer: section.viewer)
        XCTAssertEqual(detail.viewer, viewer)
        XCTAssertFalse(detail.hasCurrentViewer)
        let requests = rig.api.requests.count
        await detail.load()
        await detail.toggleFavorite()
        XCTAssertEqual(rig.api.requests.count, requests)
    }

    @MainActor
    func testLateSupplementaryProfileResponsesCannotReplaceNewRefresh() async {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let profile = #"{"code":0,"profile":{"id":71,"rating_score":3,"is_social_hidden":true}}"#
        rig.api.enqueue("/profile/71", json: profile)
        let badges = rig.api.hold("/profile/71/badge/list")
        let blog = rig.api.hold("/channel/blog/71")
        defer { badges.respond("{}", status: 500); blog.respond("{}", status: 500) }
        let model = ProfileViewModel()
        let old = Task { await model.load(profileID: 71, session: rig.session) }
        defer { old.cancel() }
        await fulfillment(of: [badges.arrived, blog.arrived], timeout: 5)
        rig.api.enqueue("/profile/71", json: profile)
        rig.api.enqueue("/profile/71/badge/list", json: #"{"code":0,"showcased":[{"id":2}]}"#)
        rig.api.enqueue("/channel/blog/71", json: #"{"code":0,"channel":{"id":1,"cover":"https://example.invalid/new.jpg"}}"#)
        await model.load(profileID: 71, session: rig.session)
        badges.respond(#"{"code":0,"showcased":[{"id":1}]}"#)
        blog.respond(#"{"code":0,"channel":{"id":1,"cover":"https://example.invalid/old.jpg"}}"#)
        await old.value
        XCTAssertEqual(model.showcased.map(\.id), [2])
        XCTAssertEqual(model.coverURL?.lastPathComponent, "new.jpg")
    }

    @MainActor
    func testProfileLoadingForOldViewerCannotPublishAfterSignIn() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let guest = rig.session.viewerKey
        let held = rig.api.hold("/profile/71")
        defer { held.respond("{}", status: 500) }
        let model = ProfileViewModel()
        let load = Task { await model.load(profileID: 71, session: rig.session, viewer: guest) }
        defer { load.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn()
        model.invalidate(for: rig.session.viewerKey)
        held.respond(#"{"code":0,"profile":{"id":71}}"#)
        await load.value
        XCTAssertNil(model.profile)
        XCTAssertNil(model.viewerKey)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }
}
