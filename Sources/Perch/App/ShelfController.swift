import AppKit

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    init() throws {
        fatalError("unimplemented")
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        fatalError("unimplemented")
    }

    // MARK: ShelfDropHandling

    func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        fatalError("unimplemented")
    }

    // MARK: EdgeStripDelegate

    func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow) {
        fatalError("unimplemented")
    }
}
