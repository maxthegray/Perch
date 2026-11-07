import AppKit
@testable import Perch
import XCTest

final class MoveShelfReminderPolicyTests: XCTestCase {
    private func context(
        usesControlToMove: Bool = true,
        canMoveShelf: Bool = true,
        shelfMoves: Int = 0,
        lastShown: TimeInterval? = nil,
        now: TimeInterval = 10_000
    ) -> MoveShelfReminderPolicy.Context {
        .init(
            usesControlToMove: usesControlToMove,
            canMoveShelf: canMoveShelf,
            shelfMoves: shelfMoves,
            lastShown: lastShown,
            now: now
        )
    }

    func testShowsOnFirstRest() {
        XCTAssertTrue(MoveShelfReminderPolicy.shouldShow(context()))
    }

    func testStaysQuietInGrabHandleModeOrWhenLocked() {
        XCTAssertFalse(MoveShelfReminderPolicy.shouldShow(context(usesControlToMove: false)))
        XCTAssertFalse(MoveShelfReminderPolicy.shouldShow(context(canMoveShelf: false)))
    }

    func testRetiresOnceTheShelfHasBeenMoved() {
        let moves = MoveShelfReminderPolicy.retireAfterMoves
        XCTAssertTrue(MoveShelfReminderPolicy.shouldShow(context(shelfMoves: moves - 1)))
        XCTAssertFalse(MoveShelfReminderPolicy.shouldShow(context(shelfMoves: moves)))
    }

    func testWaitsOutTheCooldown() {
        let cooldown = MoveShelfReminderPolicy.cooldown
        XCTAssertFalse(MoveShelfReminderPolicy.shouldShow(context(lastShown: 10_000 - cooldown + 1)))
        XCTAssertTrue(MoveShelfReminderPolicy.shouldShow(context(lastShown: 10_000 - cooldown)))
    }

    // MARK: - Placement

    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 180, height: 40)

    func testSitsRightOfALeftShelf() {
        let shelf = NSRect(x: 0, y: 300, width: 120, height: 300)
        let frame = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: .left, pointer: NSPoint(x: 60, y: 450), visible: visible
        )
        XCTAssertEqual(frame.minX, shelf.maxX + MoveShelfReminderPolicy.gap)
        XCTAssertEqual(frame.midY, 450)
    }

    func testSitsLeftOfARightShelf() {
        let shelf = NSRect(x: 1320, y: 300, width: 120, height: 300)
        let frame = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: .right, pointer: NSPoint(x: 1380, y: 450), visible: visible
        )
        XCTAssertEqual(frame.maxX, shelf.minX - MoveShelfReminderPolicy.gap)
    }

    func testSitsBelowTheNotch() {
        let shelf = NSRect(x: 600, y: 700, width: 240, height: 200)
        let frame = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: .notch, pointer: NSPoint(x: 720, y: 800), visible: visible
        )
        XCTAssertEqual(frame.maxY, shelf.minY - MoveShelfReminderPolicy.gap)
        XCTAssertEqual(frame.midX, 720)
    }

    func testFreeShelfNearTheRightEdgeUsesItsLeftSide() {
        let shelf = NSRect(x: 1250, y: 300, width: 120, height: 300)
        let frame = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: nil, pointer: NSPoint(x: 1300, y: 450), visible: visible
        )
        XCTAssertEqual(frame.maxX, shelf.minX - MoveShelfReminderPolicy.gap)
    }

    func testStaysAlongsideTheShelfVertically() {
        let shelf = NSRect(x: 0, y: 300, width: 120, height: 300)
        let frame = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: .left, pointer: NSPoint(x: 60, y: 302), visible: visible
        )
        XCTAssertEqual(frame.minY, shelf.minY)
    }
}
