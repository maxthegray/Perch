import XCTest
@testable import Perch

final class ShelfHitTestPolicyTests: XCTestCase {
    /// The card's background: inside the frame, over nothing in particular.
    private func background() -> ShelfHitTestPolicy.Targets {
        var targets = ShelfHitTestPolicy.Targets()
        targets.isInsideCard = true
        return targets
    }

    func testEmptyCardAreaIsNotClaimed() {
        XCTAssertFalse(ShelfHitTestPolicy.claimsEvent(background()))
    }

    func testPointsOutsideTheCardAreNeverClaimed() {
        var targets = ShelfHitTestPolicy.Targets()
        targets.isOverRow = true
        targets.isContextClick = true
        targets.gestureInFlight = true
        XCTAssertFalse(ShelfHitTestPolicy.claimsEvent(targets))
    }

    func testEveryInteractiveTargetIsClaimed() {
        let interactive: [(String, (inout ShelfHitTestPolicy.Targets) -> Void)] = [
            ("row", { $0.isOverRow = true }),
            ("ghost row", { $0.isOverGhostRow = true }),
            ("grab handle", { $0.isOverGrabHandle = true }),
            ("trailing button", { $0.isOverTrailingButton = true }),
            ("command-drag", { $0.shelfDragModifierHeld = true }),
            ("context click", { $0.isContextClick = true }),
            ("scroll", { $0.isScrollEvent = true }),
            ("empty free tile", { $0.dismissesEmptyFreeShelf = true }),
            ("active selection", { $0.hasActiveSelection = true })
        ]

        for (name, apply) in interactive {
            var targets = background()
            apply(&targets)
            XCTAssertTrue(ShelfHitTestPolicy.claimsEvent(targets), "\(name) should be claimed")
        }
    }

    func testRightClickOnEmptyCardAreaStillOpensTheContextMenu() {
        var targets = background()
        targets.isContextClick = true
        XCTAssertTrue(ShelfHitTestPolicy.claimsEvent(targets))
    }

    func testAGestureAlreadyUnderwayKeepsEveryFollowUpEvent() {
        // A card drag or reorder tracks well past the row it started on; declining those
        // events mid-gesture would strand the card.
        var targets = background()
        targets.gestureInFlight = true
        XCTAssertTrue(ShelfHitTestPolicy.claimsEvent(targets))
    }
}
