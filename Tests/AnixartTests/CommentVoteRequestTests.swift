import Foundation
import XCTest
import AnixartKit
@testable import Anixart

/// Uses the rig's URLProtocol / .invalid host, never a live account.
final class CommentVoteRequestTests: XCTestCase {
    @MainActor
    func testRootAndReplyRepeatBothArrowsWithoutAZeroRequest() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "owning-token")
        let account = try XCTUnwrap(rig.session.accountKey)
        for commentID in [9, 10] {
            for vote in CommentVote.allCases {
                let endpoints = [CommentEndpoints.vote(commentID: commentID, vote: vote),
                                 ProfileCommentEndpoints.vote(commentID: commentID, category: .releases, vote: vote)]
                for endpoint in endpoints {
                    let path = "/\(endpoint.path)"
                    for _ in 0..<2 {
                        rig.api.enqueue(path, json: #"{"code":0}"#)
                        let response = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                        XCTAssertEqual(response.code, 0)
                    }
                    let requests = Array(rig.api.requests(to: path).suffix(2))
                    XCTAssertEqual(requests.count, 2)
                    XCTAssertEqual(requests.first?.url, requests.last?.url)
                    for request in requests {
                        XCTAssertEqual(request.httpMethod, "GET")
                        XCTAssertEqual(request.url?.path, "/release/comment/vote/\(commentID)/\(vote.rawValue)")
                        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
                        XCTAssertEqual(query?.first { $0.name == "token" }?.value, "owning-token")
                    }
                    XCTAssertEqual(rig.session.accountKey, account)
                }
            }
        }
        XCTAssertFalse(rig.api.requests.contains { $0.url?.path.hasSuffix("/vote/9/0") == true || $0.url?.path.hasSuffix("/vote/10/0") == true })
    }

    @MainActor
    func testLateReplyVoteFailureCannotAffectTheNewAccount() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "previous-token")
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoint = ProfileCommentEndpoints.vote(commentID: 10, category: .releases, vote: .negative)
        let held = rig.api.hold("/\(endpoint.path)")
        defer { held.respond("{}", status: 500) }
        let task = Task { try await rig.session.sendConfirmedAccountRequest(endpoint, for: account) }
        defer { task.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        try await rig.signIn(profileID: 43, token: "current-token")
        let current = rig.session.accountKey
        held.respond(#"{"code":402}"#)
        do {
            _ = try await task.value
            XCTFail("An old account's vote failure must become cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(rig.session.accountKey, current)
        XCTAssertTrue(held.request?.url?.query?.contains("token=previous-token") == true)
    }
}
