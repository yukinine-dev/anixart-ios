import Foundation
import XCTest
@testable import AnixartKit

/// These requests are only built locally. Response tests use a URLProtocol and
/// a reserved .invalid host, never an Anixart account or the real API.
final class ProfileEndpointTests: XCTestCase {
    private func client(tokenStore: any TokenStore = InMemoryTokenStore(token: "test-token", profileID: 42)) -> AnixartClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileContractURLProtocol.self]
        return AnixartClient(
            configuration: .init(baseURL: URL(string: "https://profile-contract.invalid/")!),
            tokenStore: tokenStore,
            sessionConfiguration: configuration
        )
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private func query(_ request: URLRequest) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func responding<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>, with body: String) -> Endpoint<Response> {
        var endpoint = endpoint
        endpoint.headers["X-Test-Response"] = body
        return endpoint
    }

    func testSocialEditUsesCamelCaseAndKeepsClearedFields() async throws {
        let request = try await client().urlRequest(for: ProfilePreferenceEndpoints.editSocial(
            .init(vkPage: "https://vk.com/example", tgPage: "example")
        ))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/profile/preference/social/edit")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        let body = try json(request)
        XCTAssertEqual(Set(body.keys), ["vkPage", "tgPage", "instPage", "ttPage", "discordPage"])
        XCTAssertEqual(body["vkPage"] as? String, "https://vk.com/example")
        XCTAssertEqual(body["tgPage"] as? String, "example")
        XCTAssertEqual(body["instPage"] as? String, "")
        XCTAssertEqual(body["ttPage"] as? String, "")
        XCTAssertEqual(body["discordPage"] as? String, "")
    }

    func testStatusPrivacySectionAndThemeUseTheirAndroidBodies() async throws {
        let client = client()
        let status = try await client.urlRequest(for: ProfilePreferenceEndpoints.editStatus("Статус ✨"))
        XCTAssertEqual(try json(status)["status"] as? String, "Статус ✨")
        XCTAssertEqual(status.url?.path, "/profile/preference/status/edit")

        for field in ProfilePreferenceEndpoints.PrivacyField.allCases {
            let request = try await client.urlRequest(for: ProfilePreferenceEndpoints.editPrivacy(field, permission: 2))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/profile/preference/privacy/\(field.rawValue)/edit")
            XCTAssertEqual(try json(request)["permission"] as? Int, 2)
        }
        let section = try await client.urlRequest(for: ProfilePreferenceEndpoints.pinSection(.badges))
        XCTAssertEqual(section.url?.path, "/profile/preference/section/edit")
        XCTAssertEqual(try json(section)["id"] as? Int, 5)
        let theme = try await client.urlRequest(for: ProfilePreferenceEndpoints.selectTheme(id: -7))
        XCTAssertEqual(theme.url?.path, "/profile/preference/themes/edit")
        XCTAssertEqual(try json(theme)["id"] as? Int, -7)
    }

    func testAvatarMultipartPreservesBinaryBytesAndEmptyNamePart() async throws {
        let bytes = Data([0xFF, 0xD8, 0x00, 0x80, 0xFE, 0xD9])
        let request = try await client().urlRequest(for: ProfilePreferenceEndpoints.editAvatar(jpeg: bytes))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/profile/preference/avatar/edit")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary=Anixart-"))
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: bytes))
        XCTAssertNotNil(body.range(of: Data("name=\"image\"; filename=\"avatar.jpg\"\r\n".utf8)))
        XCTAssertNotNil(body.range(of: Data("name=\"name\"\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\r\n".utf8)))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertTrue(body.suffix(Data("--\(boundary)--\r\n".utf8).count).elementsEqual(Data("--\(boundary)--\r\n".utf8)))
    }

    func testMultipartHeadersCannotInjectAnotherPartOrHeader() {
        let body = MultipartBody(parts: [
            .init(name: "im\"age\r\n", filename: "a\\b\"\r\n.jpg", contentType: "image/jpeg\r\n", data: Data([0]))
        ], boundary: "test\r\n boundary:é")
        XCTAssertEqual(body.boundary, "testboundary")
        let text = String(decoding: body.encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"im%22age%0D%0A\"; filename=\"a%5Cb%22%0D%0A.jpg\"\r\n"))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("--testboundary--\r\n"))
    }

    func testLoginInfoAndChangeAreBodylessPostRequests() async throws {
        let client = client()
        let info = try await client.urlRequest(for: ProfilePreferenceEndpoints.loginInfo())
        XCTAssertEqual(info.httpMethod, "POST")
        XCTAssertNil(info.httpBody)
        let change = try await client.urlRequest(for: ProfilePreferenceEndpoints.changeLogin("new name"))
        XCTAssertEqual(change.httpMethod, "POST")
        XCTAssertEqual(change.url?.path, "/profile/preference/login/change")
        XCTAssertEqual(try query(change)["login"], "new name")
        XCTAssertNil(change.httpBody)
    }

    func testEmailAndPasswordKeepTheirDistinctFormKeys() async throws {
        let client = client()
        let email = try await client.urlRequest(for: ProfilePreferenceEndpoints.changeEmail(
            currentEmail: "a@b.c", currentPassword: "p&word", newEmail: "d@e.f"
        ))
        XCTAssertEqual(String(data: try XCTUnwrap(email.httpBody), encoding: .utf8),
                       "current_email=a%40b.c&current_password=p%26word&new_email=d%40e.f")
        let verify = try await client.urlRequest(for: ProfilePreferenceEndpoints.verifyEmail(newEmail: "d@e.f", code: 123, hash: "h"))
        XCTAssertEqual(verify.httpMethod, "GET")
        XCTAssertEqual(try query(verify)["code"], "123")
        XCTAssertEqual(try query(verify)["new_email"], "d@e.f")
        XCTAssertNil(verify.httpBody)
        let password = try await client.urlRequest(for: ProfilePreferenceEndpoints.changePassword(current: "old", new: "new"))
        XCTAssertEqual(String(data: try XCTUnwrap(password.httpBody), encoding: .utf8), "current=old&new=new")
    }

    func testDeletionStatusAloneAcceptsNotFoundAndIgnoresNullableDates() async throws {
        let client = client()
        XCTAssertEqual(ProfileSecurityEndpoints.deletionStatus().acceptedStatusCodes, [0, 3])
        XCTAssertEqual(ProfileSecurityEndpoints.requestDeletion(password: "test").acceptedStatusCodes, [0])
        XCTAssertEqual(ProfileSecurityEndpoints.cancelDeletion().acceptedStatusCodes, [0])
        let empty = try await client.send(responding(ProfileSecurityEndpoints.deletionStatus(), with: #"{"code":3}"#))
        XCTAssertEqual(empty.hasDeletionRequest, false)
        let active = try await client.send(responding(ProfileSecurityEndpoints.deletionStatus(), with: #"{"code":0,"requested_at":null,"delete_at":null}"#))
        XCTAssertEqual(active.hasDeletionRequest, true)
        for endpoint in [ProfileSecurityEndpoints.requestDeletion(password: "test"), ProfileSecurityEndpoints.cancelDeletion()] {
            do {
                _ = try await client.send(responding(endpoint, with: #"{"code":3}"#))
                XCTFail("A mutation must not accept code 3")
            } catch let error as AnixartError {
                guard case .api(let code, let path) = error else { return XCTFail("Unexpected error: \(error)") }
                XCTAssertEqual(code, 3)
                XCTAssertEqual(path, endpoint.path)
            }
        }
    }

    func testBareArrayEnforcementsStillReportAPIEnvelopeFailures() async throws {
        let endpoint = ProfileSecurityEndpoints.enforcements(account: false, page: 2)
        let client = client()
        let request = try await client.urlRequest(for: endpoint)
        XCTAssertEqual(request.url?.path, "/profile/health/enforcement/content/all/2")
        let empty = try await client.send(responding(endpoint, with: "[]"))
        XCTAssertTrue(empty.isEmpty)
        do {
            _ = try await client.send(responding(endpoint, with: #"{"code":2}"#))
            XCTFail("Expected a business error, not an array shape error")
        } catch let error as AnixartError {
            guard case .api(let code, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(code, 2)
        }
    }

    func testAdjustmentAppealSendsExplicitNullMessage() async throws {
        let request = try await client().urlRequest(for: ProfileSecurityEndpoints.appeal(id: 8))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/profile/health/enforcement/8/appeal")
        XCTAssertTrue(try json(request)["message"] is NSNull)
    }

    func testCommentRoutesAndRepliesPreserveAllThreeCategories() async throws {
        let client = client()
        for category in ProfileCommentCategory.allCases {
            let location = ProfileCommentLocation(category: category, parentID: 10)
            let detail = try await client.urlRequest(for: ProfileCommentEndpoints.comment(id: 12, category: category))
            XCTAssertEqual(detail.url?.path, "/\(category.rawValue)/comment/12")
            let all = try await client.urlRequest(for: ProfileCommentEndpoints.all(at: location, page: 3))
            XCTAssertEqual(all.url?.path, "/\(category.rawValue)/comment/all/10/3")
            let replies = try await client.urlRequest(for: ProfileCommentEndpoints.replies(commentID: 12, category: category, page: 1, sort: 0))
            XCTAssertEqual(replies.httpMethod, "POST")
            XCTAssertEqual(replies.url?.path, "/\(category.rawValue)/comment/replies/12/1")
            XCTAssertEqual(try query(replies)["sort"], "0")
            XCTAssertNil(replies.httpBody)
            let add = try await client.urlRequest(for: ProfileCommentEndpoints.add(at: location, request: .init(
                message: "reply", parentCommentId: 12, replyToProfileId: 42, spoiler: true
            )))
            XCTAssertEqual(add.httpMethod, "POST")
            XCTAssertEqual(add.url?.path, "/\(category.rawValue)/comment/add/10")
            let body = try json(add)
            XCTAssertEqual(body["parentCommentId"] as? Int, 12)
            XCTAssertEqual(body["replyToProfileId"] as? Int, 42)
            XCTAssertNil(body["parent_comment_id"])
            XCTAssertNil(body["reply_to_profile_id"])
            XCTAssertEqual(body["spoiler"] as? Bool, true)
            XCTAssertNil(body["is_spoiler"])
        }
    }

    func testAddingReleaseToCollectionUsesGetAndReleaseQuery() async throws {
        let request = try await client().urlRequest(for: CollectionEndpoints.addRelease(collectionID: 9, releaseID: 71))
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/collectionMy/release/add/9")
        XCTAssertEqual(try query(request)["release_id"], "71")
        XCTAssertEqual(try query(request)["token"], "test-token")
        XCTAssertNil(request.httpBody)
    }

    func testChannelArticlesReadUsesBodylessPostAndCoverUsesMultipart() async throws {
        let client = client()
        let articles = try await client.urlRequest(for: ChannelEndpoints.articles(channelID: 7, page: 2))
        XCTAssertEqual(articles.httpMethod, "POST")
        XCTAssertEqual(articles.url?.path, "/channel/7/article/all/2")
        XCTAssertNil(articles.httpBody)
        let cover = try await client.urlRequest(for: ChannelEndpoints.uploadCover(channelID: 7, jpeg: Data([0xFF, 0x00])))
        XCTAssertEqual(cover.url?.path, "/channel/cover/upload/7")
        XCTAssertTrue(try XCTUnwrap(cover.value(forHTTPHeaderField: "Content-Type")).hasPrefix("multipart/form-data;"))
    }

    func testBadgeRecentIsCSVAndForeignDefaultIsAnExplicitEmptyString() async throws {
        let client = client()
        let own = try await client.urlRequest(for: ProfileBadgeEndpoints.sections(profileID: 42, recent: "101,102"))
        XCTAssertEqual(own.httpMethod, "GET")
        XCTAssertEqual(own.url?.path, "/profile/42/badge/list")
        XCTAssertEqual(try query(own)["recent"], "101,102")
        XCTAssertEqual(try query(own)["token"], "test-token")
        let foreign = try await client.urlRequest(for: ProfileBadgeEndpoints.sections(profileID: 71))
        XCTAssertEqual(try query(foreign)["recent"], "")
        XCTAssertNil(foreign.httpBody)
    }

    func testFullAndReplySortsStayOnTheirOwnEndpointsAndPreserveServerOrder() async throws {
        let client = client()
        let location = ProfileCommentLocation(category: .articles, parentID: 42)
        let fixtures: [(ProfileCommentSort, [Int])] = [
            (.newest, [5, 4, 3, 2, 1]), (.oldest, [1, 2, 3, 4, 5]), (.popular, [2, 1, 4, 3, 5])
        ]
        for (sort, ids) in fixtures {
            let full = ProfileCommentEndpoints.all(at: location, page: 0, sort: sort.rawValue)
            let request = try await client.urlRequest(for: full)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/article/comment/all/42/0")
            XCTAssertEqual(try query(request)["sort"], String(sort.rawValue))
            let replies = try await client.urlRequest(for: ProfileCommentEndpoints.replies(commentID: 7, category: .articles,
                                                                                           page: 0, sort: sort.rawValue))
            XCTAssertEqual(replies.httpMethod, "POST")
            XCTAssertEqual(replies.url?.path, "/article/comment/replies/7/0")
            XCTAssertEqual(try query(replies)["sort"], String(sort.rawValue))
            let content = ids.map { "{\"id\":\($0)}" }.joined(separator: ",")
            let response = try await client.send(responding(full, with:
                "{\"code\":0,\"content\":[\(content)],\"total_count\":5,\"total_page_count\":1}"))
            // Do not invent client-side vote tie-breaking or sort the server rows.
            XCTAssertEqual(response.items.map(\.id), ids)
            XCTAssertEqual(response.totalCount, 5)
        }
    }

    func testPublicValidationDoesNotEvenReadTokenStore() async throws {
        let store = ProfileCountingTokenStore()
        let client = client(tokenStore: store)
        let login = try await client.urlRequest(for: AuthEndpoints.checkLogin("example"))
        let badge = try await client.urlRequest(for: ProfileBadgeEndpoints.preview(code: "example"))
        XCTAssertNil(try query(login)["token"])
        XCTAssertNil(try query(badge)["token"])
        let reads = await store.tokenReads
        XCTAssertEqual(reads, 0)
    }

    func testMatchingTokenRefusesAReplacementSessionToken() async throws {
        var endpoint = ProfilePreferenceEndpoints.editStatus("text")
        endpoint.auth = .matchingToken("old-token")
        do {
            _ = try await client().urlRequest(for: endpoint)
            XCTFail("Must not borrow the new session token")
        } catch let error as AnixartError {
            guard case .notAuthenticated = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testTokenReplacementIsAtomicAndChecksOwningProfile() async throws {
        let store = InMemoryTokenStore(token: "old", profileID: 42)
        let wrongToken = try await store.replace(token: "wrong", profileID: 42, expectedToken: "other")
        let wrongProfile = try await store.replace(token: "wrong", profileID: 43, expectedToken: "old")
        XCTAssertFalse(wrongToken)
        XCTAssertFalse(wrongProfile)
        let replaced = try await store.replace(token: "new", profileID: 42, expectedToken: "old")
        XCTAssertTrue(replaced)
        let token = await store.token()
        let profileID = await store.profileID()
        XCTAssertEqual(token, "new")
        XCTAssertEqual(profileID, 42)
    }
}

private final class ProfileContractURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let body = request.value(forHTTPHeaderField: "X-Test-Response"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])
        else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor ProfileCountingTokenStore: TokenStore {
    private(set) var tokenReads = 0
    func token() -> String? { tokenReads += 1; return "test-token" }
    func profileID() -> Int? { 42 }
    func save(token: String, profileID: Int) {}
    func replace(token: String, profileID: Int, expectedToken: String) -> Bool { false }
    func clear() {}
}
