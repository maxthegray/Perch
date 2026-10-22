import XCTest
@testable import Perch

final class HoverRevealPolicyTests: XCTestCase {
    func testHoverRevealCanBeTurnedOff() {
        XCTAssertFalse(
            HoverRevealPolicy.armsReveal(revealOnHoverEnabled: false, usesEdgeDock: true)
        )
        XCTAssertTrue(
            HoverRevealPolicy.armsReveal(revealOnHoverEnabled: true, usesEdgeDock: true)
        )
    }

    func testAFreeFloatingShelfHasNoEdgeToHover() {
        XCTAssertFalse(
            HoverRevealPolicy.armsReveal(revealOnHoverEnabled: true, usesEdgeDock: false)
        )
    }

    func testAPointerThatBrushedPastNeverCompletesItsReveal() {
        XCTAssertFalse(
            HoverRevealPolicy.completesArmedReveal(
                revealOnHoverEnabled: true,
                pointerStillInCatchZone: false
            )
        )
    }

    func testADwellingPointerCompletesItsReveal() {
        XCTAssertTrue(
            HoverRevealPolicy.completesArmedReveal(
                revealOnHoverEnabled: true,
                pointerStillInCatchZone: true
            )
        )
    }

    func testTurningHoverRevealOffMidDwellCancelsTheArmedReveal() {
        XCTAssertFalse(
            HoverRevealPolicy.completesArmedReveal(
                revealOnHoverEnabled: false,
                pointerStillInCatchZone: true
            )
        )
    }

    func testALiveGhostLetsAHoverRevealWithHoverRevealOff() {
        XCTAssertTrue(
            HoverRevealPolicy.armsReveal(
                revealOnHoverEnabled: false,
                hasLiveGhosts: true,
                usesEdgeDock: true
            )
        )
        XCTAssertTrue(
            HoverRevealPolicy.completesArmedReveal(
                revealOnHoverEnabled: false,
                hasLiveGhosts: true,
                pointerStillInCatchZone: true
            )
        )
    }

    func testALiveGhostStillNeedsADwell() {
        XCTAssertFalse(
            HoverRevealPolicy.completesArmedReveal(
                revealOnHoverEnabled: false,
                hasLiveGhosts: true,
                pointerStillInCatchZone: false
            )
        )
    }

    func testALiveGhostDoesNotGiveAFreeFloatingShelfAnEdge() {
        XCTAssertFalse(
            HoverRevealPolicy.armsReveal(
                revealOnHoverEnabled: false,
                hasLiveGhosts: true,
                usesEdgeDock: false
            )
        )
    }
}
