import XCTest
@testable import Perch

final class VendModePolicyTests: XCTestCase {
    func testMoveDefaultMovesWithoutOption() {
        XCTAssertFalse(VendModePolicy.copiesItems(
            copiesByDefault: false,
            optionKeyDown: false
        ))
    }

    func testOptionForcesCopyFromMoveDefault() {
        XCTAssertTrue(VendModePolicy.copiesItems(
            copiesByDefault: false,
            optionKeyDown: true
        ))
    }

    func testCopyDefaultAlwaysCopies() {
        XCTAssertTrue(VendModePolicy.copiesItems(
            copiesByDefault: true,
            optionKeyDown: false
        ))
        XCTAssertTrue(VendModePolicy.copiesItems(
            copiesByDefault: true,
            optionKeyDown: true
        ))
    }
}
