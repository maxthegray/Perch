import XCTest
@testable import Perch

final class ShelfMouseEventPolicyTests: XCTestCase {
    func testAnInvisiblePanelDoesNotTakeThePointer() {
        // The whole point: alpha 0 and mid-fade-out windows are still hit-tested by the
        // window server, so they must be told to ignore mouse events explicitly.
        XCTAssertFalse(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .revealing, dragActive: false)
        )
        XCTAssertFalse(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .hiding, dragActive: false)
        )
        XCTAssertFalse(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .hidden, dragActive: false)
        )
    }

    func testAVisiblePanelTakesThePointer() {
        XCTAssertTrue(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .revealed, dragActive: false)
        )
        XCTAssertTrue(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .revealed, dragActive: true)
        )
    }

    func testADragCanDropOnTheCardDuringItsFadeIn() {
        // The drop routinely lands inside the 0.30s reveal; a card that ignored mouse
        // events for that long would refuse it.
        XCTAssertTrue(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .revealing, dragActive: true)
        )
    }

    func testADragDoesNotResurrectARetractingPanel() {
        XCTAssertFalse(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .hiding, dragActive: true)
        )
        XCTAssertFalse(
            ShelfMouseEventPolicy.panelAcceptsMouseEvents(phase: .hidden, dragActive: true)
        )
    }

    func testEdgeStripsAreClickThroughUntilADragNeedsThem() {
        XCTAssertFalse(ShelfMouseEventPolicy.edgeStripAcceptsMouseEvents(dragActive: false))
        XCTAssertTrue(ShelfMouseEventPolicy.edgeStripAcceptsMouseEvents(dragActive: true))
    }
}
