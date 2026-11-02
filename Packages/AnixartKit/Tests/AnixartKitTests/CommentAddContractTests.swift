import Foundation
import XCTest
@testable import AnixartKit

/// Offline CommentAddRequest / CommentAddResponse contract from the reference APK.
final class CommentAddContractTests: XCTestCase {
    func testReleaseReplyUsesPostJsonRootAndRecipientNotTheReplyIdInThePath() async throws {
        let client = AnixartClient(configuration: .init(baseURL: URL(string: "https://comment-add-tests.invalid/")!),
                                  tokenStore: InMemoryTokenStore(token: "owner", profileID: 42))
        let body = CommentAddRequest(message: "Text reply", parentCommentId: 9, replyToProfileId: 44, spoiler: true)
        let legacy = try await client.urlRequest(for: CommentEndpoints.add(releaseID: 71, body))
        let profile = try await client.urlRequest(for: ProfileCommentEndpoints.add(at: .init(category: .releases, parentID: 71), request: body))
        for request in [legacy, profile] {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/release/comment/add/71")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
            let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query, [URLQueryItem(name: "token", value: "owner")])
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["message", "parentCommentId", "replyToProfileId", "spoiler"])
            XCTAssertEqual(json["message"] as? String, "Text reply")
            XCTAssertEqual(json["parentCommentId"] as? Int, 9)
            XCTAssertEqual(json["replyToProfileId"] as? Int, 44)
            XCTAssertEqual(json["spoiler"] as? Bool, true)
        }
    }

    func testTextSubmissionCodesAreNotVoteCodesOrLoginErrors() {
        let path = "release/comment/add/71"
        let messages = [
            2: "Вы не можете комментировать этот релиз, поскольку он был удалён.",
            3: "Комментарий, на который вы отвечаете, не найден.",
            4: "Пользователь, которому вы отвечаете, не найден.",
            5: "Ваш комментарий слишком короткий. Дайте свободу мысли!",
            6: "Ваш комментарий слишком длинный. Краткость – сестра таланта!",
            7: "Вы превысили допустимый лимит по комментариям за сутки. Попробуйте оставить комментарий позже.",
            8: "Пользователь внёс Вас в свой блоклист. Вы не можете отвечать на его комментарии."
        ]
        for (code, message) in messages {
            let error = AnixartError.api(code: code, path: path)
            XCTAssertEqual(error.errorDescription, message)
            XCTAssertFalse(error.isBan)
            XCTAssertNotEqual(error.errorDescription, AnixartError.api(code: code, path: "release/comment/vote/9/2").errorDescription)
        }
        XCTAssertEqual(CommentAddStatus.inBlocklist, 8)
        XCTAssertEqual(CommentAddStatus.commentLimitReached, 7)
        XCTAssertEqual(AnixartError.api(code: 2, path: "auth/signIn").errorDescription, "Неверный никнейм или email")
        XCTAssertEqual(AnixartError.api(code: 3, path: "auth/signIn").errorDescription, "Неверный пароль")
    }

    func testAddPreservesRealAccountBansAndCategorySpecificMissingParentMessages() {
        for category in ProfileCommentCategory.allCases {
            let path = "\(category.rawValue)/comment/add/71"
            XCTAssertNil(CommentAddStatus.message(code: 402, path: path))
            XCTAssertNil(CommentAddStatus.message(code: 403, path: path))
            XCTAssertEqual(AnixartError.api(code: 402, path: path).errorDescription, "Действие недоступно: аккаунт заблокирован")
            XCTAssertEqual(AnixartError.api(code: 403, path: path).errorDescription, "Действие недоступно: аккаунт заблокирован навсегда")
            XCTAssertTrue(AnixartError.api(code: 402, path: path).isBan)
            XCTAssertTrue(AnixartError.api(code: 403, path: path).isBan)
        }
        XCTAssertEqual(CommentAddStatus.message(code: 2, path: "collection/comment/add/71"), "Вы не можете комментировать эту коллекцию, поскольку она была удалена.")
        XCTAssertEqual(CommentAddStatus.message(code: 2, path: "article/comment/add/71"), "Вы не можете комментировать эту запись, поскольку она была удалена.")
        XCTAssertNil(CommentAddStatus.message(code: 8, path: "release/comment/vote/9/2"))
    }
}
