import AppKit

/// The shelf window: a non-activating panel that floats above ordinary app windows
/// on every Space, never takes key focus, and stays *below* the menu bar.
final class ShelfPanel: NSPanel {
    init(contentRect: NSRect) {
        // T0.1: configure as `.nonactivatingPanel`, window `level = .floating`
        // (NOT `.statusBar`/`.mainMenu+`, which sit above the menu bar; Decision L2),
        // collectionBehavior `[.canJoinAllSpaces, .fullScreenAuxiliary]`.
        fatalError("unimplemented")
    }

    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override var canBecomeKey: Bool { false }
}
