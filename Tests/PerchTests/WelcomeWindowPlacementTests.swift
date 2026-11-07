import AppKit
import XCTest
@testable import Perch

final class WelcomeWindowPlacementTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 75, width: 1512, height: 874)

    func testAWindowThatFitsIsLeftAlone() {
        XCTAssertNil(WelcomeWindowPlacement.clampedFrame(for: NSSize(width: 460, height: 700), in: visible))
    }

    func testATallWindowIsKeptClearOfTheDockAndMenuBar() throws {
        let frame = try XCTUnwrap(
            WelcomeWindowPlacement.clampedFrame(for: NSSize(width: 460, height: 901), in: visible)
        )
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.width, 460)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertGreaterThan(frame.height, visible.height - 2 * WelcomeWindowPlacement.margin - 1)
    }

    func testASideDockIsRespectedToo() throws {
        let leftDock = NSRect(x: 80, y: 0, width: 1352, height: 949)
        let frame = try XCTUnwrap(
            WelcomeWindowPlacement.clampedFrame(for: NSSize(width: 460, height: 1100), in: leftDock)
        )
        XCTAssertTrue(leftDock.contains(frame))
    }
}
