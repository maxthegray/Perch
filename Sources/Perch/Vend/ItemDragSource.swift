import AppKit

/// RE-VEND: the concrete `NSDraggingSource` for one or more stored items.
/// Created and **retained by the host view** for the drag's duration. Pins the
/// operation mask to `.copy` for file-backed items so the holding-dir master is
/// never moved or relocated out of the shelf.
@MainActor
final class ItemDragSource: NSObject, NSDraggingSource {
    private let items: [StoredItem]
    private var activeWriters: [StoredItemDragWriter] = []

    /// Called when the drag session ends, with the operation the destination
    /// performed (empty == no drop). Used to apply move semantics (remove the row
    /// once it has actually landed somewhere).
    var onEnded: ((NSDragOperation) -> Void)?

    /// Called off the main actor when a file-promise vend completes, with the recorded
    /// movement. The host hops it back to the main actor to append to the ledger.
    var recordVend: (@Sendable (ProvenanceEntry) -> Void)?

    /// Called off the main actor when a file-promise write fails after the drop landed
    /// (e.g. the destination denied the write). The host puts the retired row back so
    /// the item isn't silently lost.
    var onWriteFailed: (@Sendable () -> Void)?

    init(items: [StoredItem]) {
        precondition(!items.isEmpty)
        self.items = items
        super.init()
    }

    /// Start the session from `view`, with `self` as the dragging source.
    func beginDrag(from view: NSView, event: NSEvent) -> NSDraggingSession {
        let draggingItems = self.draggingItems()
        let location = view.convert(event.locationInWindow, from: nil)
        for (index, draggingItem) in draggingItems.enumerated() {
            let offset = CGFloat(min(index, 4)) * 4
            draggingItem.setDraggingFrame(
                NSRect(x: location.x - 24 + offset, y: location.y - 24 - offset, width: 48, height: 48),
                contents: items[index].iconImage()
            )
        }

        return view.beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    /// One pasteboard writer per stored item lets Finder and other destinations receive
    /// the selection as distinct files rather than one compound pasteboard item.
    func draggingItems() -> [NSDraggingItem] {
        activeWriters = items.map {
            StoredItemDragWriter(item: $0, recordVend: recordVend, onWriteFailed: onWriteFailed)
        }
        return zip(items, activeWriters).map { item, writer in
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(
                NSRect(x: 0, y: 0, width: 48, height: 48),
                contents: item.iconImage()
            )
            return draggingItem
        }
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
