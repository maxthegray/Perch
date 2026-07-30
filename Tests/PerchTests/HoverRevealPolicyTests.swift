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
}
