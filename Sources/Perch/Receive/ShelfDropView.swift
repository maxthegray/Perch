import AppKit

/// Receives a dropped pasteboard and routes it into the STORE pipeline.
@MainActor
protocol ShelfDropHandling: AnyObject {
    func handleDrop(_ pasteboard: NSPasteboard, fromPerch: Bool) -> Bool
    /// The pointer (hover or drag) entered the shelf panel's bounds (keep it open).
    func pointerDidEnterShelf()
    /// The pointer left the shelf panel's bounds (retract back to the tab).
    /// `duringDrag` is true when a drag session left (vs a plain hover), which needs a
    /// brief grace to bridge the tab↔panel hand-off; a hover exit retracts immediately.
    func pointerDidExitShelf(duringDrag: Bool)
    /// A drag is now hovering over (true) or has left/dropped onto (false) the shelf's
    /// drop area — drives the accent drop-target outline.
    func dragOverShelfDidChange(_ over: Bool)
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
        dropHandler?.pointerDidExitShelf(duringDrag: false)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dragOperation(for: sender)
        NSLog("Perch DROPDBG draggingEntered op=\(operation.rawValue) bounds=\(NSStringFromRect(bounds))")
        if !operation.isEmpty {
            dropHandler?.pointerDidEnterShelf()
            dropHandler?.dragOverShelfDidChange(true)
        }
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NSLog("Perch DROPDBG draggingExited")
        dropHandler?.dragOverShelfDidChange(false)
        dropHandler?.pointerDidExitShelf(duringDrag: true)
    }

    /// Report `.copy` so the source app takes no action on the original — the shelf
    /// performs the actual move itself (the snapshotter moves the file into the
    /// holding dir), which avoids a conflict with the source's own handling.
    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.availableType(from: Self.acceptedTypes) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A drop doesn't fire draggingExited, so snap the outline off here.
        dropHandler?.dragOverShelfDidChange(false)
        let perchSource = sender.draggingSource as? ItemDragSource
        let ok = dropHandler?.handleDrop(
            sender.draggingPasteboard,
            fromPerch: perchSource != nil
        ) ?? false
        if ok {
            perchSource?.markReturnedToPerch()
        }
        NSLog("Perch DROPDBG performDragOperation ok=\(ok)")
        return ok
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        NSLog("Perch DROPDBG prepareForDragOperation")
        return true
    }
}
