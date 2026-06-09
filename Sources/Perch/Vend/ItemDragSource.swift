import AppKit

/// RE-VEND: the concrete `NSDraggingSource` for a stored item (Decisions K, L).
/// Created and **retained by the host view** for the drag's duration. Pins the
/// operation mask to `.copy` for file-backed items so the holding-dir master is
/// never moved or relocated out of the shelf.
@MainActor
final class ItemDragSource: NSObject, NSDraggingSource {
    private let item: StoredItem
    private var activeWriter: StoredItemDragWriter?

    /// Called when the drag session ends, with the operation the destination
    /// performed (empty == no drop). Used to apply move semantics (remove the row
    /// once it has actually landed somewhere).
    var onEnded: ((NSDragOperation) -> Void)?

    /// Called off the main actor when a file-promise vend completes, with the recorded
    /// movement. The host hops it back to the main actor to append to the ledger.
    var recordVend: (@Sendable (ProvenanceEntry) -> Void)?

    init(item: StoredItem) {
        self.item = item
        super.init()
    }

    /// Start the session from `view`, with `self` as the dragging source.
    func beginDrag(from view: NSView, event: NSEvent) -> NSDraggingSession {
        let draggingItem = draggingItem()
        let location = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(
            x: location.x - 24,
            y: location.y - 24,
            width: 48,
            height: 48
        )
        draggingItem.setDraggingFrame(frame, contents: item.iconImage())

        return view.beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// The single dragging item backing this drag (promise-preferred file delivery
    /// + lazy generic data + convenience file URL — see `StoredItemDragWriter`).
    func draggingItem() -> NSDraggingItem {
        let writer = StoredItemDragWriter(item: item, recordVend: recordVend)
        activeWriter = writer

        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(
            NSRect(x: 0, y: 0, width: 48, height: 48),
            contents: item.iconImage()
        )
        return draggingItem
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // `.copy` for file-backed items, in BOTH .withinApplication and
        // .outsideApplication contexts — the destination receives a fresh copy; the
        // shelf then removes its own copy (move semantics handled in `onEnded`).
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onEnded?(operation)
    }
}
