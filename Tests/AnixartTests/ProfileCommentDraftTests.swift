import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ProfileCommentDraftTests: XCTestCase {
    private let location = ProfileCommentLocation(category: .articles, parentID: 73)

    @MainActor
    func testSendingFreezesTextSpoilerRootAndReplyTargetBeforeSuspension() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "  Original reply\n"
        draft.isSpoiler = true
        draft.replyingTo = try profileTestDecode(ProfileComment.self, #"{"id":9,"parent_comment_id":2,"profile":{"id":44}}"#)
        let held = rig.api.hold("/article/comment/add/73")
        defer { held.respond("{}", status: 500) }
        let send = Task { await draft.send(at: location, parentCommentID: 2, session: rig.session) }
        defer { send.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        draft.message = "New unsent text"
        draft.isSpoiler = false
        draft.replyingTo = nil
        let body = try XCTUnwrap(held.request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["message"] as? String, "Original reply")
        XCTAssertEqual(json["spoiler"] as? Bool, true)
        XCTAssertEqual(json["parentCommentId"] as? Int, 2)
        XCTAssertEqual(json["replyToProfileId"] as? Int, 44)
        held.respond(#"{"code":0}"#)
        let sent = await send.value
        XCTAssertTrue(sent)
        XCTAssertEqual(draft.message, "New unsent text")
        XCTAssertFalse(draft.isSpoiler)
        XCTAssertNil(draft.replyingTo)
    }

    @MainActor
    func testCodeOnlySuccessClearsOnlyTheUnchangedSentDraft() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Reply"
        draft.isSpoiler = true
        rig.api.enqueue("/article/comment/add/73", json: #"{"code":0}"#)
        let sent = await draft.send(at: location, session: rig.session)
        XCTAssertTrue(sent)
        XCTAssertEqual(draft.message, "")
        XCTAssertFalse(draft.isSpoiler)
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testEmptyOrErrorResponseNeverDiscardsUnsentDraft() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        for body in ["{}", #"{"code":2}"#] {
            draft.message = "Keep this text"
            draft.isSpoiler = true
            rig.api.enqueue("/article/comment/add/73", json: body)
            let sent = await draft.send(at: location, session: rig.session)
            XCTAssertFalse(sent)
            XCTAssertEqual(draft.message, "Keep this text")
            XCTAssertTrue(draft.isSpoiler)
            XCTAssertNotNil(draft.errorMessage)
        }
    }

    @MainActor
    func testCommentPayloadWithoutSuccessfulCodeNeverDiscardsUnsentDraft() async throws {
        for category in ProfileCommentCategory.allCases {
            let rig = ProfileTestRig()
            try await rig.signIn()
            let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
            let location = ProfileCommentLocation(category: category, parentID: 73)
            let path = "/\(category.rawValue)/comment/add/73"
            for json in [#"{"comment":{"id":9}}"#, #"{"code":null,"comment":{"id":9}}"#, #"{"code":2,"comment":{"id":9}}"#] {
                draft.message = "Keep this text"
                draft.isSpoiler = true
                rig.api.enqueue(path, json: json)
                let sent = await draft.send(at: location, session: rig.session)
                XCTAssertFalse(sent)
                XCTAssertEqual(draft.message, "Keep this text")
                XCTAssertTrue(draft.isSpoiler)
                XCTAssertNotNil(draft.errorMessage)
                XCTAssertFalse(draft.isSending)
            }
            rig.api.enqueue(path, json: #"{"code":0,"comment":{"id":9}}"#)
            let sent = await draft.send(at: location, session: rig.session)
            XCTAssertTrue(sent)
            XCTAssertEqual(draft.message, "")
            XCTAssertFalse(draft.isSpoiler)
            XCTAssertNil(draft.errorMessage)
            XCTAssertEqual(rig.api.requests(to: path).count, 4)
        }
    }

    @MainActor
    func testConcurrentSendCannotSubmitTheSameDraftTwice() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Reply"
        let held = rig.api.hold("/article/comment/add/73")
        defer { held.respond("{}", status: 500) }
        let first = Task { await draft.send(at: location, session: rig.session) }
        defer { first.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        let second = await draft.send(at: location, session: rig.session)
        XCTAssertFalse(second)
        XCTAssertEqual(rig.api.requests(to: "/article/comment/add/73").count, 1)
        held.respond(#"{"code":0}"#)
        let sent = await first.value
        XCTAssertTrue(sent)
    }

    @MainActor
    func testInvalidParentRootOrReplyProfileNeverSendsARequest() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Reply"
        let before = rig.api.requests.count
        let invalidLocation = await draft.send(at: .init(category: .articles, parentID: 0), session: rig.session)
        let invalidRoot = await draft.send(at: location, parentCommentID: 0, session: rig.session)
        let invalidProfile = await draft.send(at: location, defaultReplyToProfileID: -1, session: rig.session)
        XCTAssertFalse(invalidLocation)
        XCTAssertFalse(invalidRoot)
        XCTAssertFalse(invalidProfile)
        XCTAssertEqual(rig.api.requests.count, before)
        XCTAssertEqual(draft.message, "Reply")
    }

    @MainActor
    func testGuestDraftPromptsLoginButCannotBorrowNewSession() async throws {
        let rig = ProfileTestRig()
        await rig.session.restore()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Guest text"
        let sentAsGuest = await draft.send(at: location, session: rig.session)
        XCTAssertFalse(sentAsGuest)
        XCTAssertTrue(rig.session.isPresentingAuth)
        XCTAssertEqual(draft.message, "Guest text")
        try await rig.signIn()
        let sentWithNewSession = await draft.send(at: location, session: rig.session)
        XCTAssertFalse(sentWithNewSession)
        XCTAssertEqual(draft.message, "")
        XCTAssertTrue(rig.api.requests(to: "/article/comment/add/73").isEmpty)
    }

    @MainActor
    func testLateSendSuccessAfterSameProfileLoginCannotClearNewDraftOrReportSuccess() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "first")
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Old account text"
        let held = rig.api.hold("/article/comment/add/73")
        defer { held.respond("{}", status: 500) }
        let send = Task { await draft.send(at: location, session: rig.session) }
        defer { send.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(token: "second")
        draft.invalidate(for: rig.session.viewerKey)
        held.respond(#"{"code":0}"#)
        let sent = await send.value
        XCTAssertFalse(sent)
        XCTAssertEqual(draft.message, "")
        XCTAssertNil(draft.errorMessage)
        XCTAssertFalse(draft.isSending)
        let retry = await draft.send(at: location, session: rig.session)
        XCTAssertFalse(retry)
        XCTAssertEqual(rig.api.requests(to: "/article/comment/add/73").count, 1)
    }

    @MainActor
    func testCancelledSendKeepsDraftAndDoesNotShowCancellationError() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let draft = ProfileCommentDraft(viewer: rig.session.viewerKey)
        draft.message = "Unsent"
        let held = rig.api.hold("/article/comment/add/73")
        defer { held.respond("{}", status: 500) }
        let send = Task { await draft.send(at: location, session: rig.session) }
        defer { send.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        send.cancel()
        let sent = await send.value
        XCTAssertFalse(sent)
        XCTAssertEqual(draft.message, "Unsent")
        XCTAssertNil(draft.errorMessage)
        XCTAssertFalse(draft.isSending)
    }
}
