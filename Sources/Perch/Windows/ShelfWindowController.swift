import AppKit

/// Reveals / hides / animates the shelf panel and persists its frame.
@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel

    init(panel: ShelfPanel) {
        self.panel = panel
    }

    func reveal(animated: Bool) {
        fatalError("unimplemented")
    }

    func hide(animated: Bool) {
        fatalError("unimplemented")
    }

    func restorePersistedFrame() {
        fatalError("unimplemented")
    }

    func persistFrame() {
        fatalError("unimplemented")
    }
}
