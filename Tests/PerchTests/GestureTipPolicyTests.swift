import XCTest
@testable import Perch

final class GestureTipPolicyTests: XCTestCase {
    private func moveTip(
        alreadyShown: Bool = false,
        showsGrabHandle: Bool = false,
        isPlainDrag: Bool = true,
        canMoveShelf: Bool = true,
        dragDistance: CGFloat = 40
    ) -> Bool {
        GestureTipPolicy.showsMoveShelfTip(
            alreadyShown: alreadyShown,
            showsGrabHandle: showsGrabHandle,
            isPlainDrag: isPlainDrag,
            canMoveShelf: canMoveShelf,
            dragDistance: dragDistance
        )
    }

    private func copyTip(
        alreadyShown: Bool = false,
        copiesByDefault: Bool = false,
        optionHeld: Bool = false,
        landedOutsidePerch: Bool = true,
        cardStaysVisible: Bool = true
    ) -> Bool {
        GestureTipPolicy.showsKeepCopyTip(
            alreadyShown: alreadyShown,
            copiesByDefault: copiesByDefault,
            optionHeld: optionHeld,
            landedOutsidePerch: landedOutsidePerch,
            cardStaysVisible: cardStaysVisible
        )
    }

    func testPlainBackgroundDragInControlModeShowsMoveTip() {
        XCTAssertTrue(moveTip())
    }

    func testMoveTipShowsOnlyOnce() {
        XCTAssertFalse(moveTip(alreadyShown: true))
    }

    func testMoveTipNeverShowsInHandleMode() {
        XCTAssertFalse(moveTip(showsGrabHandle: true))
    }

    func testMoveTipNeedsAPlainDrag() {
        XCTAssertFalse(moveTip(isPlainDrag: false))
    }

    func testMoveTipStaysQuietWhenTheShelfCannotMove() {
        XCTAssertFalse(moveTip(canMoveShelf: false))
    }

    func testShortWobbleIsNotADrag() {
        XCTAssertFalse(moveTip(dragDistance: GestureTipPolicy.inertDragThreshold - 1))
        XCTAssertTrue(moveTip(dragDistance: GestureTipPolicy.inertDragThreshold))
    }

    func testMoveModeVendShowsCopyTip() {
        XCTAssertTrue(copyTip())
    }

    func testCopyTipShowsOnlyOnce() {
        XCTAssertFalse(copyTip(alreadyShown: true))
    }

    func testCopyTipSkippedWhenCopyIsTheDefault() {
        XCTAssertFalse(copyTip(copiesByDefault: true))
    }

    func testCopyTipSkippedWhenOptionAlreadyHeld() {
        XCTAssertFalse(copyTip(optionHeld: true))
    }

    func testCopyTipNeedsARealExternalLanding() {
        XCTAssertFalse(copyTip(landedOutsidePerch: false))
    }

    func testCopyTipWaitsWhenTheCardIsGoingAway() {
        XCTAssertFalse(copyTip(cardStaysVisible: false))
    }
}

final class GestureShortcutsTests: XCTestCase {
    private func rows(
        showsGrabHandle: Bool = false,
        copiesByDefault: Bool = false,
        revealOnHover: Bool = false,
        shakeToSummon: Bool = false,
        shelvesOnEdgeTouch: Bool = true
    ) -> [GestureShortcut] {
        GestureShortcuts.rows(
            showsGrabHandle: showsGrabHandle,
            copiesByDefault: copiesByDefault,
            revealOnHover: revealOnHover,
            shakeToSummon: shakeToSummon,
            shelvesOnEdgeTouch: shelvesOnEdgeTouch
        )
    }

    func testDefaultsListEveryCoreGesture() {
        XCTAssertEqual(rows().map(\.action), [
            "Keep a copy", "Move shelf", "Add to selection", "Select range",
            "Quick Look", "Menu", "Show shelf", "Tuck away"
        ])
    }

    func testMoveRowFollowsTheGestureMode() {
        XCTAssertEqual(
            rows(showsGrabHandle: false).first { $0.action == "Move shelf" },
            GestureShortcut(key: "⌃", gesture: "Drag", action: "Move shelf")
        )
        XCTAssertEqual(
            rows(showsGrabHandle: true).first { $0.action == "Move shelf" },
            GestureShortcut(gesture: "Drag handle", action: "Move shelf")
        )
    }

    func testCopyByDefaultDropsTheOptionCopyRow() {
        XCTAssertFalse(rows(copiesByDefault: true).contains { $0.action == "Keep a copy" })
    }

    func testRevealOnHoverDropsTheOptionEdgeRow() {
        XCTAssertFalse(rows(revealOnHover: true).contains { $0.action == "Show shelf" })
    }

    func testOptionalGesturesAppearOnlyWhenEnabled() {
        XCTAssertFalse(rows(shelvesOnEdgeTouch: false).contains { $0.action == "Tuck away" })
        XCTAssertTrue(rows(shakeToSummon: true).contains { $0.action == "Summon shelf" })
        XCTAssertFalse(rows().contains { $0.action == "Summon shelf" })
    }
}
