import Foundation
import XCTest
@testable import AnixartKit

/// Offline contract from the supplied 10.5 APK (SHA256 ecca1727…82d00).
/// No request is sent: URL construction and response interpretation only.
final class CommentVoteContractTests: XCTestCase {
    private func client(token: String? = "fixture-token") -> AnixartClient {
        AnixartClient(configuration: .init(baseURL: URL(string: "https://comment-tests.invalid/")!),
                      tokenStore: InMemoryTokenStore(token: token, profileID: token == nil ? nil : 42))
    }

    private func endpoints(commentID: Int, vote: CommentVote) -> [Endpoint<StatusResponse>] {
        [CommentEndpoints.vote(commentID: commentID, vote: vote)]
            + ProfileCommentCategory.allCases.map {
                ProfileCommentEndpoints.vote(commentID: commentID, category: $0, vote: vote)
            }
    }

    func testOnlyArrowValuesAreValidRequests() throws {
        XCTAssertEqual(CommentVote.allCases.map(\.rawValue), [1, 2])
        XCTAssertEqual(CommentVote.negative.rawValue, 1)
        XCTAssertEqual(CommentVote.positive.rawValue, 2)
        for invalid in [0, -1, 3] { XCTAssertNil(CommentVote(rawValue: invalid)) }
        XCTAssertEqual(try JSONDecoder().decode(CommentVote.self, from: Data("2".utf8)), .positive)
    }

    func testRootAndReplyVotesUseTheSameGetToggleContract() async throws {
        let client = client()
        for commentID in [9, 10] {
            for vote in CommentVote.allCases {
                for endpoint in endpoints(commentID: commentID, vote: vote) {
                    let first = try await client.urlRequest(for: endpoint)
                    let repeated = try await client.urlRequest(for: endpoint)
                    XCTAssertEqual(first.url, repeated.url, "A repeated arrow must not become /0")
                    XCTAssertTrue(first.url?.path.hasSuffix("/comment/vote/\(commentID)/\(vote.rawValue)") == true)
                    XCTAssertEqual(first.httpMethod, "GET")
                    XCTAssertNil(first.httpBody)
                    let query = URLComponents(url: try XCTUnwrap(first.url), resolvingAgainstBaseURL: false)?.queryItems
                    XCTAssertEqual(query, [URLQueryItem(name: "token", value: "fixture-token")])
                    XCTAssertEqual(endpoint.acceptedStatusCodes, [0])
                }
                let legacy = try await client.urlRequest(for: CommentEndpoints.vote(commentID: commentID, vote: vote))
                let profile = try await client.urlRequest(for: ProfileCommentEndpoints.vote(commentID: commentID, category: .releases, vote: vote))
                XCTAssertEqual(legacy.url, profile.url)
            }
        }
    }

    func testBothArrowsRequireAuthentication() async {
        let guest = client(token: nil)
        for vote in CommentVote.allCases {
            for endpoint in endpoints(commentID: 9, vote: vote) {
                do {
                    _ = try await guest.urlRequest(for: endpoint)
                    XCTFail("A guest vote must not be constructed")
                } catch {
                    XCTAssertEqual(error as? AnixartError, .notAuthenticated(path: endpoint.path))
                }
            }
        }
    }

    func testDecodedRootAndReplyStatesSelectTheCorrectArrow() throws {
        for isReply in [false, true] {
            for rawValue in [0, 1, 2] {
                let json = "{\"id\":10,\"release\":71,\"parent_comment_id\":\(isReply ? 9 : 0),\"is_reply\":\(isReply),\"vote\":\(rawValue),\"vote_count\":-4}"
                let data = Data(json.utf8)
                let release = try JSONDecoder().decode(ReleaseComment.self, from: data)
                let profile = try JSONDecoder().decode(ProfileComment.self, from: data)
                XCTAssertEqual(release.vote, rawValue)
                XCTAssertEqual(profile.vote, rawValue)
                XCTAssertEqual(profile.voteCount, -4)
                XCTAssertEqual(profile.threadRootID, isReply ? 9 : 10)
                XCTAssertEqual(ProfileComment(releaseComment: release).vote, profile.vote)
                for vote in CommentVote.allCases {
                    XCTAssertEqual(vote.isSelected(currentVote: release.vote), rawValue == vote.rawValue)
                    XCTAssertEqual(vote.isSelected(currentVote: profile.vote), rawValue == vote.rawValue)
                }
            }
        }
        for vote in CommentVote.allCases {
            XCTAssertFalse(vote.isSelected(currentVote: nil))
            XCTAssertFalse(vote.isSelected(currentVote: -1))
        }
    }

    func testCommentVoteCodesHaveTheApkMessagesNotSignInErrors() {
        let messages = [
            2: "Вы превысили дневной лимит на отрицательные оценки",
            3: "Кажется, Вы зарегистрированы совсем недавно. Побудьте с нами немного дольше, чтобы получить возможность ставить оценки.",
            402: "Вы не можете голосовать, поскольку ваш аккаунт заблокирован",
            403: "Вы не можете голосовать, поскольку ваш аккаунт заблокирован навсегда"
        ]
        XCTAssertEqual(CommentVoteStatus.negativeVoteLimitReached, 2)
        XCTAssertEqual(CommentVoteStatus.insufficientAccountAge, 3)
        for vote in CommentVote.allCases {
            for endpoint in endpoints(commentID: 10, vote: vote) {
                for (code, message) in messages {
                    let error = AnixartError.api(code: code, path: endpoint.path)
                    XCTAssertEqual(error.errorDescription, message)
                    XCTAssertEqual(error.isBan, code == 402 || code == 403)
                }
                let unknown = AnixartError.api(code: 99, path: endpoint.path)
                XCTAssertEqual(unknown.errorDescription, "Сервер отклонил запрос \(endpoint.path) (код 99)")
                XCTAssertFalse(unknown.isBan)
            }
        }
    }

    func testErrorMappingDoesNotChangeAuthOrOtherRoutes() {
        XCTAssertEqual(AnixartError.api(code: 2, path: "auth/signIn").errorDescription, "Неверный никнейм или email")
        XCTAssertEqual(AnixartError.api(code: 3, path: "auth/signIn").errorDescription, "Неверный пароль")
        for path in ["release/71", "release/comment/votes/9/0", "article/vote/9/1", "release/comment/add/71"] {
            XCTAssertNil(CommentVoteStatus.message(code: 2, path: path))
            XCTAssertEqual(AnixartError.api(code: 402, path: path).errorDescription, "Действие недоступно: аккаунт заблокирован")
        }
    }

    func testReleaseListsAndRepliesKeepTheirApkMethodsAndSorts() async throws {
        let client = client()
        let comments = try await client.urlRequest(for: CommentEndpoints.comments(releaseID: 71, page: 0))
        XCTAssertEqual(comments.httpMethod, "GET")
        XCTAssertEqual(comments.url?.path, "/release/comment/all/71/0")
        XCTAssertTrue(comments.url?.query?.contains("sort=1") == true)
        let replies = try await client.urlRequest(for: CommentEndpoints.replies(commentID: 9, page: 0))
        XCTAssertEqual(replies.httpMethod, "POST")
        XCTAssertEqual(replies.url?.path, "/release/comment/replies/9/0")
        XCTAssertTrue(replies.url?.query?.contains("sort=2") == true)
        XCTAssertNil(replies.httpBody)
    }
}
