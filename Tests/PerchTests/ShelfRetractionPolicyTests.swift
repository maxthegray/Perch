import XCTest
@testable import Perch

final class ShelfRetractionPolicyTests: XCTestCase {
    func testAnyActiveSystemDragBlocksAutomaticRetraction() {
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: true,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
    }

    func testEmptyEdgeShelfMayRetractAfterDragEndsOutsideKeepAliveRegion() {
        XCTAssertTrue(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
    }

    func testOtherExistingVisibilityHoldsStillBlockRetraction() {
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: true,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: true,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: true,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: true
            )
        )
    }

    // MARK: - Undoing an accidental hover

    func testAnUnusedHoverRevealRetractsEvenHoldingItems() {
        // The reported bug: one brush past the screen edge parked a card — and with it a
        // region that swallowed clicks — over the app underneath, for good.
        XCTAssertTrue(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .unusedHover,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: false,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
    }

    func testAShelfHoldingItemsStaysOutOnceItHasBeenUsed() {
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractShelf(
                reveal: .used,
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: false,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
    }

    func testAnUnusedHoverRevealStillRespectsEveryVisibilityHold() {
        // Being undoable must not make it retract out from under a live gesture.
        let holds: [(name: String, dragActive: Bool, shelfDrag: Bool, free: Bool, pointer: Bool, menu: Bool)] = [
            ("system drag", true, false, false, false, false),
            ("card drag", false, true, false, false, false),
            ("free floating", false, false, true, false, false),
            ("pointer still on it", false, false, false, true, false),
            ("context menu open", false, false, false, false, true)
        ]

        for hold in holds {
            XCTAssertFalse(
                ShelfRetractionPolicy.shouldRetractShelf(
                    reveal: .unusedHover,
                    dragActive: hold.dragActive,
                    shelfDragActive: hold.shelfDrag,
                    isFreeFloating: hold.free,
                    isEmpty: false,
                    pointerInKeepAliveRegion: hold.pointer,
                    contextMenuOpen: hold.menu
                ),
                "\(hold.name) should hold the shelf open"
            )
        }
    }
}
