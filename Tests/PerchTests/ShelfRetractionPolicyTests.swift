import XCTest
@testable import Perch

final class ShelfRetractionPolicyTests: XCTestCase {
    func testAnyActiveSystemDragBlocksAutomaticRetraction() {
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
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
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
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
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
                dragActive: false,
                shelfDragActive: true,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: true,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: true,
                contextMenuOpen: false
            )
        )
        XCTAssertFalse(
            ShelfRetractionPolicy.shouldRetractEmptyShelf(
                dragActive: false,
                shelfDragActive: false,
                isFreeFloating: false,
                isEmpty: true,
                pointerInKeepAliveRegion: false,
                contextMenuOpen: true
            )
        )
    }
}
