import AppKit

/// Receives a dropped pasteboard and routes it into the STORE pipeline.
@MainActor
protocol ShelfDropHandling: AnyObject {
    func handleDrop(_ pasteboard: NSPasteboard) -> Bool
    /// The pointer (hover or drag) entered the shelf panel's bounds (keep it open).
    func pointerDidEnterShelf()
    /// The pointer left the shelf panel's bounds (retract back to the tab).
    func pointerDidExitShelf()
}

/// The panel's drop target (`NSDraggingDestination`).
final class ShelfDropView: NSView {
    weak var dropHandler: ShelfDropHandling?

    private static let concreteAcceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .string,
        .rtf,
        .tiff,
        .URL,
        .html
    ]

    /// Dragged types the shelf accepts (file URL, file promise, string, RTF, TIFF,
    /// URL, HTML, …). Populated in T3.
    static let acceptedTypes: [NSPasteboard.PasteboardType] =
        concreteAcceptedTypes + NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        dropHandler?.pointerDidEnterShelf()
    }

    override func mouseExited(with event: NSEvent) {
        dropHandler?.pointerDidExitShelf()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: Self.acceptedTypes) != nil else {
            return []
        }

        dropHandler?.pointerDidEnterShelf()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHandler?.pointerDidExitShelf()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandler?.handleDrop(sender.draggingPasteboard) ?? false
    }
}
