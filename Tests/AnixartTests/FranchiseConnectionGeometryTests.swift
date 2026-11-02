import XCTest
@testable import Anixart

final class FranchiseConnectionGeometryTests: XCTestCase {
    func testMiddleRowsConnectAcrossTheirInsets() {
        XCTAssertEqual(FranchiseConnectionGeometry.segment(height: 220, first: false, last: false), 0...220)
    }
    func testEndsStopAtPosterCentres() {
        XCTAssertEqual(FranchiseConnectionGeometry.segment(height: 220, first: true, last: false), 94...220)
        XCTAssertEqual(FranchiseConnectionGeometry.segment(height: 220, first: false, last: true), 0...94)
        XCTAssertEqual(FranchiseConnectionGeometry.segment(height: 220, first: true, last: true), 94...94)
    }
}
