import XCTest
@testable import Perch

final class EdgeShelvingGestureTests: XCTestCase {
    func testHoldingAtWallCannotRepeatToggleAcrossVisibilityChanges() {
        var gesture = EdgeShelvingGesture()
        gesture.updateContact(isTouchingWall: true)
        XCTAssertFalse(gesture.requiresWallExit)
        gesture.consumeContact()

        for _ in 0..<20 {
            gesture.updateContact(isTouchingWall: true)
            XCTAssertTrue(gesture.requiresWallExit)
        }

        gesture.updateContact(isTouchingWall: false)
        gesture.updateContact(isTouchingWall: true)
        XCTAssertFalse(gesture.requiresWallExit)
        gesture.consumeContact()
        XCTAssertTrue(gesture.requiresWallExit)
    }

    func testRevealOrTransferConsumesExistingContactUntilPointerLeaves() {
        var gesture = EdgeShelvingGesture()
        gesture.consumeContact()
        gesture.updateContact(isTouchingWall: true)
        XCTAssertTrue(gesture.requiresWallExit)
        gesture.updateContact(isTouchingWall: false)
        XCTAssertFalse(gesture.requiresWallExit)
    }
}
