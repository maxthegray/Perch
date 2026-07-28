import Foundation
import XCTest
@testable import Perch

@MainActor
final class VendDeliveryTrackerTests: XCTestCase {
    func testLandingRetiresEveryItemWhoseDeliveryHasNotFailed() {
        let items = makeItems(count: 3)
        let recorder = Recorder()
        let tracker = makeTracker(items: items, recorder: recorder)

        tracker.promiseDidWrite(itemID: items[0].id)
        tracker.promiseDidFail(itemID: items[1].id)
        tracker.dragDidLand()

        XCTAssertEqual(recorder.retired, [items[0].id, items[2].id])
        XCTAssertEqual(recorder.restored, [])
    }

    func testFailureAfterLandingRestoresOnlyTheItemThatFailed() {
        let items = makeItems(count: 3)
        let recorder = Recorder()
        let tracker = makeTracker(items: items, recorder: recorder)

        tracker.dragDidLand()
        XCTAssertEqual(recorder.retired, items.map(\.id))

        tracker.promiseDidWrite(itemID: items[0].id)
        tracker.promiseDidFail(itemID: items[1].id)

        XCTAssertEqual(recorder.restored, [items[1].id])
    }

    func testFailureBeforeLandingIsRememberedRatherThanLost() {
        let items = makeItems(count: 2)
        let recorder = Recorder()
        let tracker = makeTracker(items: items, recorder: recorder)

        // The background write result beat AppKit's drag-ended callback to the main
        // actor — the row must never be retired in the first place.
        tracker.promiseDidFail(itemID: items[0].id)
        tracker.dragDidLand()

        XCTAssertEqual(recorder.retired, [items[1].id])
        XCTAssertEqual(recorder.restored, [])
    }

    func testCancelledDragNeitherRetiresNorRestores() {
        let items = makeItems(count: 2)
        let recorder = Recorder()
        let tracker = makeTracker(items: items, recorder: recorder)

        tracker.dragDidNotLand()
        tracker.promiseDidFail(itemID: items[0].id)
        tracker.promiseDidWrite(itemID: items[1].id)

        XCTAssertEqual(recorder.retired, [])
        XCTAssertEqual(recorder.restored, [])
    }

    func testCopyModeLeavesTheShelfUntouched() {
        let items = makeItems(count: 2)
        let recorder = Recorder()
        let tracker = makeTracker(
            items: items,
            appliesMoveSemantics: false,
            recorder: recorder
        )

        tracker.dragDidLand()
        tracker.promiseDidFail(itemID: items[0].id)

        XCTAssertEqual(recorder.retired, [])
        XCTAssertEqual(recorder.restored, [])
    }

    func testRepeatedAndUnknownResultsDoNotRestoreTwice() {
        let items = makeItems(count: 1)
        let recorder = Recorder()
        let tracker = makeTracker(items: items, recorder: recorder)

        tracker.dragDidLand()
        tracker.promiseDidFail(itemID: items[0].id)
        tracker.promiseDidFail(itemID: items[0].id)
        tracker.promiseDidFail(itemID: UUID())
        tracker.dragDidLand()

        XCTAssertEqual(recorder.retired, [items[0].id])
        XCTAssertEqual(recorder.restored, [items[0].id])
    }

    // MARK: Helpers

    private final class Recorder {
        var retired: [UUID] = []
        var restored: [UUID] = []
    }

    private func makeTracker(
        items: [StoredItem],
        appliesMoveSemantics: Bool = true,
        recorder: Recorder
    ) -> VendDeliveryTracker {
        VendDeliveryTracker(
            items: items,
            appliesMoveSemantics: appliesMoveSemantics,
            retire: { recorder.retired.append($0.id) },
            restore: { recorder.restored.append($0.id) }
        )
    }

    /// `VendDeliveryTracker` only reads identity off its items, so these need no
    /// backing directory.
    private func makeItems(count: Int) -> [StoredItem] {
        (0..<count).map { index in
            let id = UUID()
            return StoredItem(
                metadata: ItemMetadata(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                    title: "item-\(index).png",
                    representations: [],
                    backingFileNames: ["item-\(index).png"],
                    primaryFileType: "public.png",
                    originPaths: nil
                ),
                directoryURL: URL(fileURLWithPath: "/tmp/perch-tests/\(id.uuidString)")
            )
        }
    }
}
