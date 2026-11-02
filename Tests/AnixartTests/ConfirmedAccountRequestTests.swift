import Foundation
import XCTest
import AnixartKit
@testable import Anixart

final class ConfirmedAccountRequestTests: XCTestCase {
    @MainActor
    private func assertCancelled<Value: Sendable>(_ task: Task<Value, Error>, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await task.value; XCTFail("Expected cancellation", file: file, line: line) }
        catch { XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)", file: file, line: line) }
    }

    @MainActor
    func testMissingOrNullCodeDoesNotConfirmStatusOnlyMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoint = ProfilePreferenceEndpoints.editPrivacy(.statistics, permission: 2)
        for json in ["{}", #"{"code":null}"#] {
            rig.api.enqueue("/\(endpoint.path)", json: json)
            do {
                _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                XCTFail("An unacknowledged mutation must not succeed: \(json)")
            } catch {
                XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не подтвердил изменение", path: endpoint.path))
            }
            XCTAssertEqual(rig.session.accountKey, account)
        }
        XCTAssertEqual(rig.api.requests(to: "/\(endpoint.path)").count, 2)
    }

    @MainActor
    func testPayloadWithoutSuccessfulCodeDoesNotConfirmMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoint = ProfilePreferenceEndpoints.editStatus("saved")
        for json in [#"{"status":"saved"}"#, #"{"code":null,"status":"saved"}"#] {
            rig.api.enqueue("/\(endpoint.path)", json: json)
            do {
                _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                XCTFail("A payload is not a mutation acknowledgement")
            } catch {
                XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не подтвердил изменение", path: endpoint.path))
            }
        }
    }

    @MainActor
    func testSuccessfulCodeReturnsTypedResponseAndUsesOwningToken() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn(token: "owning-token")
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoint = ProfilePreferenceEndpoints.editStatus("saved")
        rig.api.enqueue("/\(endpoint.path)", json: #"{"code":0,"status":"saved"}"#)
        let response = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.status, "saved")
        let request = try XCTUnwrap(rig.api.requests(to: "/\(endpoint.path)").first)
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "token" })?.value, "owning-token")
        XCTAssertEqual(rig.session.accountKey, account)
    }

    @MainActor
    func testBusinessErrorsRemainAPIErrorsInsteadOfAcknowledgements() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoint = ProfilePreferenceEndpoints.editPrivacy(.counts, permission: 1)
        for code in [1, 2, 3, 402, 403] {
            rig.api.enqueue("/\(endpoint.path)", json: "{\"code\":\(code)}")
            do {
                _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                XCTFail("Business failure \(code) must not succeed")
            } catch {
                XCTAssertEqual(error as? AnixartError, .api(code: code, path: endpoint.path))
            }
            XCTAssertEqual(rig.session.accountKey, account)
        }
    }

    @MainActor
    func testAcceptedNonzeroReadCodeStillCannotConfirmAMutation() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        var endpoint = ProfilePreferenceEndpoints.editPrivacy(.social, permission: 1)
        endpoint.acceptedStatusCodes = [0, 3]
        rig.api.enqueue("/\(endpoint.path)", json: #"{"code":3}"#)
        do {
            _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
            XCTFail("Accepted read codes must not relax explicit mutation confirmation")
        } catch {
            XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не подтвердил изменение", path: endpoint.path))
        }
    }

    @MainActor
    func testOptionalReadModelsStillTolerateMissingCode() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        for json in ["{}", #"{"code":null}"#] {
            rig.api.enqueue("/profile/preference/my", json: json)
            let response = try await rig.session.sendAccountRequest(ProfilePreferenceEndpoints.my(), for: account)
            XCTAssertNil(response.code)
        }
    }

    @MainActor
    func testLegacyAndProfileCommentVotesRequireExplicitSuccessfulCode() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let endpoints = CommentVote.allCases.flatMap { vote in
            [CommentEndpoints.vote(commentID: 9, vote: vote)]
                + ProfileCommentCategory.allCases.map {
                    ProfileCommentEndpoints.vote(commentID: 9, category: $0, vote: vote)
                }
        }
        for endpoint in endpoints {
            for json in ["{}", #"{"code":null}"#] {
                rig.api.enqueue("/\(endpoint.path)", json: json)
                do {
                    _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                    XCTFail("A vote without a successful code must not be confirmed")
                } catch {
                    XCTAssertEqual(error as? AnixartError, .decoding(message: "Сервер не подтвердил изменение", path: endpoint.path))
                }
            }
            for code in [1, 2, 3, 402, 403] {
                rig.api.enqueue("/\(endpoint.path)", json: "{\"code\":\(code)}")
                do {
                    _ = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
                    XCTFail("A rejected vote must not be confirmed")
                } catch {
                    XCTAssertEqual(error as? AnixartError, .api(code: code, path: endpoint.path))
                }
                XCTAssertEqual(rig.session.accountKey, account)
            }
            rig.api.enqueue("/\(endpoint.path)", json: #"{"code":0}"#)
            let response = try await rig.session.sendConfirmedAccountRequest(endpoint, for: account)
            XCTAssertEqual(response.code, 0)
        }
    }

    @MainActor
    func testStaleAccountCannotStartMutationEvenAfterSigningIntoSameProfile() async throws {
        for profileID in [42, 43] {
            let rig = ProfileTestRig()
            try await rig.signIn(token: "previous")
            let account = try XCTUnwrap(rig.session.accountKey)
            try await rig.signIn(profileID: profileID, token: "current")
            let before = rig.api.requests.count
            let mutation = Task {
                try await rig.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.remove(), for: account)
            }
            defer { mutation.cancel() }
            await assertCancelled(mutation)
            XCTAssertEqual(rig.api.requests.count, before)
            XCTAssertTrue(rig.api.requests(to: "/profile/preference/badge/remove").isEmpty)
        }
    }

    @MainActor
    func testLateAcknowledgementsAndErrorsFromOldSessionBecomeCancellation() async throws {
        for profileID in [42, 43] {
            for json in ["{}", #"{"code":null}"#, #"{"code":0}"#, #"{"code":2}"#] {
                let rig = ProfileTestRig()
                try await rig.signIn(token: "previous")
                let account = try XCTUnwrap(rig.session.accountKey)
                let held = rig.api.hold("/profile/preference/badge/remove")
                defer { held.respond("{}", status: 500) }
                let mutation = Task {
                    try await rig.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.remove(), for: account)
                }
                defer { mutation.cancel() }
                await fulfillment(of: [held.arrived], timeout: 5)
                try await rig.signIn(profileID: profileID, token: "current")
                let current = rig.session.accountKey
                held.respond(json)
                await assertCancelled(mutation)
                XCTAssertEqual(rig.session.accountKey, current)
                XCTAssertTrue(held.request?.url?.query?.contains("token=previous") == true)
            }
        }
    }

    @MainActor
    func testCancelledMutationCannotConfirmSuccess() async throws {
        let rig = ProfileTestRig()
        try await rig.signIn()
        let account = try XCTUnwrap(rig.session.accountKey)
        let held = rig.api.hold("/profile/preference/badge/remove")
        defer { held.respond("{}", status: 500) }
        let mutation = Task {
            try await rig.session.sendConfirmedAccountRequest(ProfileBadgeEndpoints.remove(), for: account)
        }
        defer { mutation.cancel() }
        await fulfillment(of: [held.arrived], timeout: 5)
        mutation.cancel()
        await assertCancelled(mutation)
        await fulfillment(of: [held.cancelled], timeout: 5)
        XCTAssertEqual(rig.session.accountKey, account)
    }
}
