import AppKit

/// Receives a dropped pasteboard and routes it into the STORE pipeline.
@MainActor
protocol ShelfDropHandling: AnyObject {
    func handleDrop(_ pasteboard: NSPasteboard) -> Bool
}

/// The panel's drop target (`NSDraggingDestination`).
final class ShelfDropView: NSView {
    weak var dropHandler: ShelfDropHandling?

    /// Dragged types the shelf accepts (file URL, file promise, string, RTF, TIFF,
    /// URL, HTML, …). Populated in T3.
    static let acceptedTypes: [NSPasteboard.PasteboardType] = []

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fatalError("unimplemented")
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fatalError("unimplemented")
    }
}
