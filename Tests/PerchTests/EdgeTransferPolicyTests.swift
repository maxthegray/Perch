import XCTest
@testable import Perch

final class EdgeTransferPolicyTests: XCTestCase {
    func testPopulatedStableEdgeShelfCanArmWhenEnabled() {
        XCTAssertTrue(canArm())
    }

    func testFeatureDefaultsToInertAndRequiresContent() {
        XCTAssertFalse(canArm(enabled: false))
        XCTAssertFalse(canArm(hasStoredItems: false))
    }

    func testTransientShelfStatesCannotArmATransfer() {
        XCTAssertFalse(canArm(panelVisible: false))
        XCTAssertFalse(canArm(panelFullyRevealed: false))
        XCTAssertFalse(canArm(usesEdgeDock: false))
        XCTAssertFalse(canArm(dragInFlight: true))
        XCTAssertFalse(canArm(shelfDragInFlight: true))
        XCTAssertFalse(canArm(arrivalPreviewActive: true))
        XCTAssertFalse(canArm(contextMenuOpen: true))
    }

    private func canArm(
        enabled: Bool = true,
        panelVisible: Bool = true,
        panelFullyRevealed: Bool = true,
        usesEdgeDock: Bool = true,
        hasStoredItems: Bool = true,
        dragInFlight: Bool = false,
        shelfDragInFlight: Bool = false,
        arrivalPreviewActive: Bool = false,
        contextMenuOpen: Bool = false
    ) -> Bool {
        EdgeTransferPolicy.canArm(
            enabled: enabled,
            panelVisible: panelVisible,
            panelFullyRevealed: panelFullyRevealed,
            usesEdgeDock: usesEdgeDock,
            hasStoredItems: hasStoredItems,
            dragInFlight: dragInFlight,
            shelfDragInFlight: shelfDragInFlight,
            arrivalPreviewActive: arrivalPreviewActive,
            contextMenuOpen: contextMenuOpen
        )
    }
}
