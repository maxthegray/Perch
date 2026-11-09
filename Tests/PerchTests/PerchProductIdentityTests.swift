import XCTest
@testable import Perch

final class PerchProductIdentityTests: XCTestCase {
    func testCallsItselfPerchLabsWhileALabsFeatureIsOn() {
        XCTAssertEqual(PerchProductIdentity.displayName(labsFeatureOn: true), "Perch Labs")
        XCTAssertEqual(PerchProductIdentity.displayName(labsFeatureOn: false), "Perch")
    }
}
