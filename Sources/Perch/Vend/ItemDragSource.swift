import AppKit

/// RE-VEND: the concrete `NSDraggingSource` for a stored item (Decisions K, L).
/// Created and **retained by the host view** for the drag's duration. Pins the
/// operation mask to `.copy` for file-backed items so the holding-dir master is
/// never moved or relocated out of the shelf.
@MainActor
final class ItemDragSource: NSObject, NSDraggingSource {
    init(item: StoredItem) {
        fatalError("unimplemented")
    }

    /// Start the session from `view`, with `self` as the dragging source.
    func beginDrag(from view: NSView, event: NSEvent) -> NSDraggingSession {
        fatalError("unimplemented")
    }

    /// The single dragging item backing this drag (promise-preferred file delivery
    /// + lazy generic data + convenience file URL — see `StoredItemDragWriter`).
    func draggingItem() -> NSDraggingItem {
        fatalError("unimplemented")
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // `.copy` for file-backed items, in BOTH .withinApplication and
        // .outsideApplication contexts (Decision K) — never move the master.
        fatalError("unimplemented")
    }
}
