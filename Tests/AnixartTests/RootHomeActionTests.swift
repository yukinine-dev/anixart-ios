import XCTest
@testable import Anixart

final class RootHomeActionTests: XCTestCase {
    @MainActor
    func testActionInvokesRootNavigationRatherThanPushingAnotherHomeView() {
        var invocations = 0
        let action = RootHomeAction { invocations += 1 }
        action()
        XCTAssertEqual(invocations, 1)
    }
}
