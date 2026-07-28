import Foundation
import XCTest
@testable import Perch

@MainActor
final class PromiseMaterializationReconcilerTests: XCTestCase {
    func testLateDeliveryThatReachesMainActorFirstJoinsInitialBatch() {
        let reconciler = PromiseMaterializationReconciler()
        let initial = URL(fileURLWithPath: "/tmp/initial.png")
        let late = URL(fileURLWithPath: "/tmp/late.png")

        XCTAssertNil(reconciler.reconcileLate(late))
        XCTAssertEqual(reconciler.reconcileInitial([initial]), [initial, late])
    }

    func testLateDeliveryAfterInitialCompletionIsReturnedImmediately() {
        let reconciler = PromiseMaterializationReconciler()
        let late = URL(fileURLWithPath: "/tmp/late.png")

        XCTAssertTrue(reconciler.reconcileInitial([]).isEmpty)
        XCTAssertEqual(reconciler.reconcileLate(late), late)
    }

    func testInitialReconciliationRemovesDuplicatePaths() {
        let reconciler = PromiseMaterializationReconciler()
        let file = URL(fileURLWithPath: "/tmp/file.png")

        XCTAssertNil(reconciler.reconcileLate(file))
        XCTAssertEqual(reconciler.reconcileInitial([file]), [file])
    }
}
