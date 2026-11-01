import Foundation
import XCTest
@testable import AnixartKit

/// Offline wire-contract checks. No request is sent to Anixart.
final class ProfileAuditContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func client() -> AnixartClient {
        AnixartClient(configuration: .init(baseURL: URL(string: "https://audit-contract.invalid/")!),
                      tokenStore: InMemoryTokenStore(token: "fixture-token", profileID: 42))
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testFriendWireValuesAndBothIDOrders() throws {
        let first = try decode(FriendStatusCode.self, "0")
        let second = try decode(FriendStatusCode.self, "1")
        XCTAssertEqual(first, .pendingFirstSecond)
        XCTAssertEqual(second, .pendingSecondFirst)
        XCTAssertEqual(try decode(FriendStatusCode.self, "2"), .friend)
        XCTAssertEqual(try decode(FriendStatusCode.self, "3"), .unknown("3"))
        XCTAssertEqual(first.relationship(firstID: 10, secondID: 20), .outgoing)
        XCTAssertEqual(first.relationship(firstID: 20, secondID: 10), .incoming)
        XCTAssertEqual(second.relationship(firstID: 10, secondID: 20), .incoming)
        XCTAssertEqual(second.relationship(firstID: 20, secondID: 10), .outgoing)
        XCTAssertEqual(try decode(FriendStatusCode.self, "null"), .none)
    }

    func testPrivacyRemovesUnavailableSections() throws {
        let counts = try decode(Profile.self, #"{"id":1,"is_counts_hidden":true}"#)
        XCTAssertEqual(counts.visibleSections, [.statistics, .votes, .badges])
        let all = try decode(Profile.self, #"{"id":1,"is_counts_hidden":true,"is_stats_hidden":true}"#)
        XCTAssertEqual(all.visibleSections, [.badges])
        XCTAssertTrue(all.hasHiddenProfileSections)
    }

    func testPrivilegeIsNotReputationAndCreationMinimumComesFromConfig() throws {
        XCTAssertFalse(ProfileCapabilities.mayUseIncognito(privilegeLevel: 1))
        XCTAssertTrue(ProfileCapabilities.mayUseIncognito(privilegeLevel: 2))
        XCTAssertTrue(ProfileCapabilities.mayModerate(viewerLevel: 3, targetLevel: 1))
        XCTAssertFalse(ProfileCapabilities.mayModerate(viewerLevel: 3, targetLevel: 2))
        let config = try decode(TogglesResponse.self, #"{"code":0,"minBlogCreateRatingScore":5}"#)
        XCTAssertEqual(ProfileCapabilities.minimumBlogReputation(toggles: config), 5)
        XCTAssertFalse(ProfileCapabilities.mayCreateBlog(reputation: 4, toggles: config))
        XCTAssertTrue(ProfileCapabilities.mayCreateBlog(reputation: 5, togggles: config))
    }

    func testAllCommentSortsUseTheVerifiedOneBasedValues() async throws {
        XCTAssertEqual(ProfileCommentSort.allCases.map(\.rawValue), [1, 2, 3])
        let client = client()
        for category in ProfileCommentCategory.allCases {
            let request = try await client.urlRequest(for: ProfileCommentEndpoints.replies(commentID: 9, category: category, page: 0))
            XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "sort" })?.value, "2")
            XCTAssertEqual(request.httpMethod, "POST")
            let voters = try await client.urlRequest(for: ProfileCommentEndpoints.voters(commentID: 9, category: category, page: 0, filter: .positive))
            XCTAssertEqual(voters.httpMethod, category == .articles ? "POST" : "GET")
            XCTAssertTrue(voters.url?.absoluteString.contains("sort=2") == true)
        }
    }

    func testReportsHaveDistinctRoutesAndCorrectBodyKeys() async throws {
        let client = client()
        for kind in [ReportTargetKind.profile, .collection, .article, .comment(.articles), .comment(.collections), .comment(.releases)] {
            let reasons = try await client.urlRequest(for: ReportEndpoints.reasons(for: kind))
            XCTAssertEqual(reasons.url?.path, "/report/\(kind.path)/reasons")
            XCTAssertEqual(reasons.httpMethod, "GET")
            let report = try await client.urlRequest(for: ReportEndpoints.send(to: kind, request: .init(entityID: 42, reasonID: 777, message: "Текст")))
            XCTAssertEqual(report.url?.path, "/report/\(kind.path)")
            XCTAssertEqual(report.httpMethod, "POST")
            let json = try body(report)
            XCTAssertEqual(Set(json.keys), ["entity_id", "reason", "message"])
            XCTAssertEqual(json["entity_id"] as? Int, 42)
            XCTAssertEqual(json["reason"] as? Int, 777)
        }
    }

    func testNotificationPreferenceSetsKeepTheirMixedWireCasing() async throws {
        let client = client()
        let statuses = try body(await client.urlRequest(for: NotificationPreferenceEndpoints.editStatuses([0, 2, 999])))
        XCTAssertEqual(statuses["profileStatusNotificationPreferences"] as? [Int], [0, 2, 999])
        let types = try body(await client.urlRequest(for: NotificationPreferenceEndpoints.editTypes([5, 9])))
        XCTAssertEqual(types["profileTypeNotificationPreferences"] as? [Int], [5, 9])
        let release = try body(await client.urlRequest(for: NotificationPreferenceEndpoints.editReleaseTypes(releaseID: 42, ids: [5])))
        XCTAssertEqual(release["profile_release_type_notification_preferences"] as? [Int], [5])
        XCTAssertEqual(release["release_id"] as? Int, 42)
        let toggle = try await client.urlRequest(for: NotificationPreferenceEndpoints.toggle(.selectedReleases))
        XCTAssertEqual(toggle.httpMethod, "GET")
        XCTAssertNil(toggle.httpBody)
        XCTAssertFalse(toggle.url?.absoluteString.contains("enabled=") == true)
    }

    func testNotificationSubtypesAndUnknownFallbackRoundTrip() throws {
        let fixtures = [
            #"{"id":1,"type":"article","is_new":true,"article":{"id":7}}"#,
            #"{"id":2,"type":"releaseComment","is_new":true,"comment":{"id":8,"release":9},"parentComment":{"id":10}}"#,
            #"{"id":3,"type":"myCollection","is_new":true,"collection_comment":{"id":11,"collection":12}}"#,
            #"{"id":4,"type":"myArticle","is_new":true,"article_comment":{"id":13,"article":14}}"#,
            #"{"id":5,"type":"future","is_new":true}"#
        ]
        for fixture in fixtures {
            let notification = try decode(AnixartNotification.self, fixture)
            XCTAssertEqual(try JSONDecoder().decode(AnixartNotification.self, from: JSONEncoder().encode(notification)), notification)
            XCTAssertFalse(notification.markedRead().base.isNew ?? true)
        }
        let item = try decode(AnixartNotification.self, fixtures[2])
        guard case .comment(let comment) = item else { return XCTFail("Expected a collection notification") }
        XCTAssertEqual(comment.category, .collections)
        XCTAssertEqual(comment.comment?.id, 11)
    }

    func testEnforcementCallbackRoutingUsesWireOrdinalsNotWhenMappingNumbers() throws {
        let invalid = try decode(ProfileEnforcement.self, #"{"id":1,"type":"article_edit","appeal_type":3,"appeal_status":1}"#)
        XCTAssertFalse(invalid.hasValidDetails)
        XCTAssertEqual(invalid.appealRoute, .none)
        let adjustment = try decode(ProfileEnforcement.self, #"{"id":1,"type":"article_edit","entity":{"id":2},"appeal_type":3,"appeal_status":1}"#)
        XCTAssertEqual(adjustment.appealRoute, .enforcementDetails)
        let message = try decode(ProfileEnforcement.self, #"{"id":1,"type":"profile_ban","appeal_type":2,"appeal_status":1}"#)
        XCTAssertEqual(message.appealRoute, .messageForm)
        let submitted = try decode(ProfileEnforcement.self, #"{"id":1,"type":"profile_ban","appeal_type":2,"appeal_status":2}"#)
        XCTAssertEqual(submitted.appealRoute, .none)
        let accepted = try decode(ProfileEnforcement.self, #"{"id":1,"type":"profile_ban","appeal_type":2,"appeal_status":3}"#)
        XCTAssertEqual(accepted.appealRoute, .result)
    }

    func testGifUploadPreservesBytesAndUtf16LimitsDoNotSplitEmoji() async throws {
        let bytes = Data([71, 73, 70, 56, 57, 97, 0, 128])
        let request = try await client().urlRequest(for: ProfilePreferenceEndpoints.editAvatar(gif: bytes))
        let data = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(data.range(of: bytes))
        XCTAssertNotNil(data.range(of: Data("filename=\"avatar.gif\"".utf8)))
        XCTAssertNotNil(data.range(of: Data("Content-Type: image/gif".utf8)))
        let limited = ProfileEditorRules.limitedText(String(repeating: "😀", count: 25), utf16Limit: 32)
        XCTAssertEqual(limited.count, 16)
        XCTAssertEqual(limited.utf16.count, 32)
        XCTAssertEqual(ProfileEditorRules.badgePreviewLimit, 7)
        XCTAssertEqual(ProfileEditorRules.categoryBadgePreviewLimit, 11)
    }
}
