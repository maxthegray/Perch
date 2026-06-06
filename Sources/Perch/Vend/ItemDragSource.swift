import AppKit

/// RE-VEND: the concrete `NSDraggingSource` for a stored item (Decisions K, L).
/// Created and **retained by the host view** for the drag's duration. Pins the
/// operation mask to `.copy` for file-backed items so the holding-dir master is
/// never moved or relocated out of the shelf.
@MainActor
final class ItemDragSource: NSObject, NSDraggingSource {
    private let item: StoredItem

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
        let pasteboardItem = NSPasteboardItem()
        let backingFileURL = item.backingFileURLs().first

        if let backingFileURL {
            pasteboardItem.setString(backingFileURL.absoluteString, forType: .fileURL)
        }

        for record in item.metadata.representations where !record.isPromisePlaceholder {
            let type = NSPasteboard.PasteboardType(record.typeIdentifier)
            if type == .fileURL, backingFileURL != nil {
                continue
            }

            guard let data = item.data(forType: type) else {
                continue
            }

            if type == .string, let string = String(data: data, encoding: .utf8) {
                pasteboardItem.setString(string, forType: type)
            } else {
                pasteboardItem.setData(data, forType: type)
            }
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
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
        // .outsideApplication contexts (Decision K) — never move the master.
        .copy
    }
}
