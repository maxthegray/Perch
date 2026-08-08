import XCTest
@testable import Perch

final class ShelfSelectionPolicyTests: XCTestCase {
    func testCommandClickTogglesMembershipAndUpdatesAnchor() {
        var policy = ShelfSelectionPolicy<String>()
        let order = ["a", "b", "c", "d"]

        policy.click("b", modifier: .plain, orderedItemIDs: order)
        policy.click("d", modifier: .command, orderedItemIDs: order)

        XCTAssertEqual(policy.selectedItemIDs, ["b", "d"])
        XCTAssertEqual(policy.anchorItemID, "d")

        policy.click("d", modifier: .command, orderedItemIDs: order)

        XCTAssertEqual(policy.selectedItemIDs, ["b"])
        XCTAssertEqual(policy.anchorItemID, "d")
    }

    func testShiftClickExtendsContiguouslyWithoutMovingAnchor() {
        var policy = ShelfSelectionPolicy<String>()
        let order = ["a", "b", "c", "d", "e"]

        policy.click("b", modifier: .plain, orderedItemIDs: order)
        policy.click("e", modifier: .shift, orderedItemIDs: order)

        XCTAssertEqual(policy.selectedItemIDs, ["b", "c", "d", "e"])
        XCTAssertEqual(policy.anchorItemID, "b")
    }

    func testShiftClickAfterCommandClickUsesCommandAnchor() {
        var policy = ShelfSelectionPolicy<String>()
        let order = ["a", "b", "c", "d", "e", "f"]

        policy.click("b", modifier: .plain, orderedItemIDs: order)
        policy.click("d", modifier: .command, orderedItemIDs: order)
        policy.click("f", modifier: .shift, orderedItemIDs: order)

        XCTAssertEqual(policy.selectedItemIDs, ["d", "e", "f"])
        XCTAssertEqual(policy.anchorItemID, "d")
    }

    func testRepeatedShiftClickReplacesThePreviousRangeFromTheSameAnchor() {
        var policy = ShelfSelectionPolicy<String>()
        let order = ["a", "b", "c", "d", "e", "f"]

        policy.click("b", modifier: .plain, orderedItemIDs: order)
        policy.click("f", modifier: .shift, orderedItemIDs: order)
        policy.click("d", modifier: .shift, orderedItemIDs: order)

        XCTAssertEqual(policy.selectedItemIDs, ["b", "c", "d"])
        XCTAssertEqual(policy.anchorItemID, "b")
    }

    func testContextClickPreservesSelectionInsideAndCollapsesOutside() {
        var policy = ShelfSelectionPolicy<String>()
        let order = ["a", "b", "c"]
        policy.click("a", modifier: .plain, orderedItemIDs: order)
        policy.click("b", modifier: .command, orderedItemIDs: order)

        policy.contextClick("a")
        XCTAssertEqual(policy.selectedItemIDs, ["a", "b"])
        XCTAssertEqual(policy.anchorItemID, "b")

        policy.contextClick("c")
        XCTAssertEqual(policy.selectedItemIDs, ["c"])
        XCTAssertEqual(policy.anchorItemID, "c")
    }

    func testGroupedReorderPreservesShelfOrderWithinSelection() {
        let reordered = ShelfSelectionReorderPolicy.reorder(
            ["a", "b", "c", "d", "e"],
            moving: ["b", "d"],
            draggedItemID: "d",
            to: 4
        )

        XCTAssertEqual(reordered, ["a", "c", "e", "b", "d"])
    }

    func testGroupedReorderKeepsBlockStationaryAtDragStart() {
        let reordered = ShelfSelectionReorderPolicy.reorder(
            ["a", "b", "c", "d"],
            moving: ["b", "c"],
            draggedItemID: "c",
            to: 2
        )

        XCTAssertEqual(reordered, ["a", "b", "c", "d"])
    }
}
