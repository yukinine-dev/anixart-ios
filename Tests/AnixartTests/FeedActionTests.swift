import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class FeedActionTests: XCTestCase {
    private func channel() throws -> Channel {
        try profileTestDecode(Channel.self, #"{"id":17,"is_blog":false,"is_subscribed":false,"subscriber_count":100}"#)
    }
    private func article() throws -> Article {
        try profileTestDecode(Article.self, #"{"id":71,"vote":0,"vote_count":100}"#)
    }

    @MainActor
    func testUnacknowledgedSubscriptionDoesNotChangeFlagsOrGlobalTotals() async throws {
        for reply in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = FeedActionsModel(session: rig.session)
            let source = try channel()
            rig.api.enqueue("/channel/subscribe/17", json: reply)
            let accepted = await model.subscribe(source, enabled: true)
            XCTAssertFalse(accepted)
            XCTAssertEqual(model.channel(source).isSubscribed, false)
            XCTAssertEqual(model.channel(source).subscriberCount, 100)
            XCTAssertEqual(model.membershipRevision, 0)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    @MainActor
    func testAcknowledgedSubscriptionIsSharedAcrossRowsAndSameChoiceIsNoOp() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedActionsModel(session: rig.session)
        let source = try channel()
        rig.api.enqueue("/channel/subscribe/17", json: #"{"code":0}"#)
        let subscribed = await model.subscribe(source, enabled: true)
        XCTAssertTrue(subscribed)
        XCTAssertEqual(model.channel(source).isSubscribed, true)
        XCTAssertEqual(model.channel(source).subscriberCount, 100)
        let count = rig.api.requests.count
        let same = await model.subscribe(source, enabled: true)
        XCTAssertTrue(same)
        XCTAssertEqual(rig.api.requests.count, count)
    }

    @MainActor
    func testUnacknowledgedVoteNeverUpdatesTheRowOrRequestsAFreshArticle() async throws {
        for reply in ["{}", #"{"code":null}"#, #"{"code":2}"#] {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let model = FeedActionsModel(session: rig.session)
            let source = try article()
            rig.api.enqueue("/article/vote/71/1", json: reply)
            let accepted = await model.vote(source, value: 1)
            XCTAssertFalse(accepted)
            XCTAssertEqual(model.article(source).vote, 0)
            XCTAssertEqual(model.article(source).voteCount, 100)
            XCTAssertTrue(rig.api.requests(to: "/article/71").isEmpty)
        }
    }

    @MainActor
    func testBlogSubscribeSendsFriendRequestToTheAuthorAndNeverChannelSubscribe() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(profileID: 42)
        let model = FeedActionsModel(session: rig.session)
        let blog = try profileTestDecode(Channel.self, #"{"id":17,"is_blog":true,"blog_profile_id":71,"is_subscribed":false}"#)
        rig.api.enqueue("/profile/friend/request/send/71", json: #"{"code":0,"friend_status":"PENDING_FIRST_SECOND"}"#)
        let sent = await model.subscribe(blog, enabled: true)
        XCTAssertTrue(sent)
        XCTAssertTrue(model.blogRequestsSent.contains(17))
        XCTAssertEqual(model.channel(blog).isSubscribed, true)
        XCTAssertTrue(rig.api.requests(to: "/channel/subscribe/17").isEmpty)
        let count = rig.api.requests.count
        let removal = await model.subscribe(blog, enabled: false)
        XCTAssertFalse(removal, "Friend removal is available through the author's explicit profile controls")
        XCTAssertEqual(rig.api.requests.count, count)
    }

    @MainActor
    func testUnknownBlogAuthorAndOwnBlogNeverDispatchSocialWrites() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(profileID: 42)
        let model = FeedActionsModel(session: rig.session)
        let count = rig.api.requests.count
        for json in [#"{"id":17,"is_blog":true}"#, #"{"id":17,"is_blog":true,"blog_profile_id":42}"#] {
            let accepted = await model.subscribe(try profileTestDecode(Channel.self, json), enabled: true)
            XCTAssertFalse(accepted)
        }
        XCTAssertEqual(rig.api.requests.count, count)
    }

    @MainActor
    func testVoteAcknowledgementSurvivesFailedReadAndRetryDoesNotVoteAgain() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedActionsModel(session: rig.session)
        let source = try article()
        rig.api.enqueue("/article/vote/71/1", json: #"{"code":0}"#)
        rig.api.enqueue("/article/71", json: #"{"code":2}"#)
        let acknowledged = await model.vote(source, value: 1)
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(model.article(source).vote, 1)
        XCTAssertEqual(model.article(source).voteCount, 100, "No invented global +1")
        XCTAssertTrue(model.articleRefreshNeeded.contains(71))
        let count = rig.api.requests.count
        let blocked = await model.vote(source, value: 1)
        XCTAssertFalse(blocked)
        XCTAssertEqual(rig.api.requests.count, count)
        rig.api.enqueue("/article/71", json: #"{"code":0,"article":{"id":71,"vote":1,"vote_count":105}}"#)
        await model.refreshArticle(id: 71)
        XCTAssertEqual(model.article(source).voteCount, 105)
        XCTAssertFalse(model.articleRefreshNeeded.contains(71))
        XCTAssertEqual(rig.api.requests(to: "/article/vote/71/1").count, 1)
    }

    @MainActor
    func testOldSupplementaryReadCannotReplaceANewerArticleSnapshot() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let model = FeedActionsModel(session: rig.session)
        let source = try article()
        let held = rig.api.hold("/article/71")
        defer { held.respond("{}", status: 500) }
        let old = Task { await model.refreshArticle(id: 71) }
        defer { old.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        rig.api.enqueue("/article/71", json: #"{"code":0,"article":{"id":71,"vote":1,"vote_count":200}}"#)
        await model.refreshArticle(id: 71)
        held.respond(#"{"code":0,"article":{"id":71,"vote":0,"vote_count":100}}"#)
        await old.value
        XCTAssertEqual(model.article(source).voteCount, 200)
        XCTAssertEqual(model.article(source).vote, 1)
    }

    @MainActor
    func testStaleAccountAndLateSubscriptionAcknowledgementCannotMutateNewSession() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let model = FeedActionsModel(session: rig.session)
        let source = try channel()
        let held = rig.api.hold("/channel/subscribe/17")
        defer { held.respond("{}", status: 500) }
        let changing = Task { await model.subscribe(source, enabled: true) }
        defer { changing.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        held.respond(#"{"code":0}"#)
        let adopted = await changing.value
        XCTAssertFalse(adopted)
        XCTAssertEqual(model.channel(source).isSubscribed, false)
        XCTAssertEqual(model.membershipRevision, 0)
        let count = rig.api.requests.count
        let stale = await model.subscribe(source, enabled: true)
        XCTAssertFalse(stale)
        XCTAssertEqual(rig.api.requests.count, count)
    }

    @MainActor
    func testGuestVoteAndSubscriptionOnlyRequestLoginAndDoNotSendWrites() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let model = FeedActionsModel(session: rig.session)
        let subscribed = await model.subscribe(try channel(), enabled: true)
        let voted = await model.vote(try article(), value: 1)
        XCTAssertFalse(subscribed)
        XCTAssertFalse(voted)
        XCTAssertTrue(rig.session.isPresentingAuth)
        XCTAssertTrue(rig.api.requests.isEmpty)
    }
}
