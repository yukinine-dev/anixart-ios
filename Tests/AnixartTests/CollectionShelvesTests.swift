import XCTest
import AnixartKit
@testable import Anixart

final class CollectionShelvesTests: XCTestCase {
    private func collection(id: Int, releases: [Int], favorite: Bool = false, creator: Int = 99) throws -> ReleaseCollection {
        let items = releases.map { "{\"id\":\($0)}" }.joined(separator: ",")
        let json = "{\"id\":\(id),\"is_favorite\":\(favorite),\"creator\":{\"id\":\(creator)},\"releases\":[\(items)]}"
        return try JSONDecoder().decode(ReleaseCollection.self, from: Data(json.utf8))
    }

    @MainActor
    func testNeedsTwoSharedReleasesAndOrdersByOverlap() throws {
        let library: Set<Int> = [1, 2, 3]
        let weak = try collection(id: 10, releases: [1, 8, 9, 7])
        let two = try collection(id: 11, releases: [1, 2, 8, 9])
        let three = try collection(id: 12, releases: [1, 2, 3, 8])
        let result = CollectionShelvesModel.rank([weak, two, three], library: library, completed: [], profileID: 1)
        XCTAssertEqual(result.map(\.id), [12, 11])
        XCTAssertEqual(result.first?.percent, 75)
    }

    @MainActor
    func testSkipsBookmarkedOwnAndFullyWatchedCollections() throws {
        let library: Set<Int> = [1, 2, 3]
        let bookmarked = try collection(id: 20, releases: [1, 2, 8], favorite: true)
        let own = try collection(id: 21, releases: [1, 2, 8], creator: 1)
        let watched = try collection(id: 22, releases: [1, 2])
        let result = CollectionShelvesModel.rank([bookmarked, own, watched], library: library, completed: [1, 2, 3], profileID: 1)
        XCTAssertTrue(result.isEmpty)
    }
}
