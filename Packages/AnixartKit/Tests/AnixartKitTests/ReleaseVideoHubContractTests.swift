import XCTest
@testable import AnixartKit

final class ReleaseVideoHubContractTests: XCTestCase {
    func testHubUsesAPKMainPathWithoutTokenOrSearchVersionOverride() async throws {
        let client = AnixartClient(tokenStore: InMemoryTokenStore(token: "test-token", profileID: 42))
        let request = try await client.urlRequest(for: ReleaseVideoEndpoints.overview(releaseID: 71))
        XCTAssertEqual(request.url?.path, "/video/release/71")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.value(forHTTPHeaderField: "API-Version"), "2")
    }

    func testHubDecodesExactMixedAPKKeysAndSeparateVideoBlocks() throws {
        let json = #"{"code":0,"release":{"id":71},"last_videos":[{"id":1,"player_url":"https://video-tests.invalid/player","profile":{"id":42},"release":71}],"blocks":[{"category":{"id":9,"name":"Опенинги"},"videos":[{"id":2}]}],"streaming_platforms":[{"id":3,"url":"https://streaming-tests.invalid/watch"}],"can_appeal":false}"#
        let response = try JSONDecoder().decode(ReleaseVideosResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.lastVideos?.first?.release?.id, 71)
        XCTAssertEqual(response.lastVideos?.first?.playerUrl, "https://video-tests.invalid/player")
        XCTAssertEqual(response.blocks?.first?.category?.id, 9)
        XCTAssertEqual(response.blocks?.first?.videos?.map(\.id), [2])
        XCTAssertEqual(response.streamingPlatforms?.first?.id, 3)
        XCTAssertEqual(response.canAppeal, false)
        let encoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        XCTAssertNotNil(encoded["last_videos"])
        XCTAssertNotNil(encoded["streaming_platforms"])
        XCTAssertNotNil(encoded["can_appeal"])
        XCTAssertNil(encoded["lastVideos"])
        XCTAssertNil(encoded["canAppeal"])
    }

    func testHubKeepsExplicitEmptyArraysDistinctFromMissingContent() throws {
        let empty = try JSONDecoder().decode(ReleaseVideosResponse.self, from: Data(#"{"code":0,"release":{"id":71},"last_videos":[],"blocks":[],"streaming_platforms":[]}"#.utf8))
        XCTAssertEqual(empty.lastVideos, [])
        XCTAssertEqual(empty.blocks, [])
        let missing = try JSONDecoder().decode(ReleaseVideosResponse.self, from: Data(#"{"code":0}"#.utf8))
        XCTAssertNil(missing.lastVideos)
        XCTAssertNil(missing.release)
    }
}
