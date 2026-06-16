import AppKit

/// Detects when a drag is in progress so the edge "drop here" tab can be shown
/// only while the user is holding something.
///
/// Watches global left-mouse-drag/up events and reports drag-session start/end.
/// Global *mouse* monitoring does **not** require Accessibility/TCC permission
/// (only keyboard events / `CGEventTap` do), so this never prompts.
@MainActor
final class MouseMonitor {
    /// Fired on the main actor when a drag begins (`true`) or ends (`false`).
    var onDragSessionChange: ((Bool) -> Void)?

    /// Fired on each drag movement with the current cursor location (screen coords).
    var onDragMoved: ((NSPoint) -> Void)?

    private var monitor: Any?
    private var isDragging = false

    /// `changeCount` of the drag pasteboard captured at mouse-down. A real
    /// drag-and-drop session writes the dragged items to this pasteboard before
    /// the first drag event, bumping the count; merely holding the button and
    /// moving the mouse (text selection, window moves, marquee selection) does
    /// not. Comparing against this baseline lets us ignore non-drag holds.
    private var dragPasteboardBaseline = 0

    init() {}

    /// Install the global drag monitor. No-op if already running.
    func start() {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
    }

    /// Remove the global monitor. Idempotent.
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if isDragging {
            isDragging = false
            onDragSessionChange?(false)
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // Snapshot the drag pasteboard so the first drag event can tell
            // whether a real drag-and-drop session was begun on this click.
            dragPasteboardBaseline = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            if !isDragging {
                // Only treat this as a drag session if the click actually
                // started a drag-and-drop (populated the drag pasteboard).
                guard NSPasteboard(name: .drag).changeCount != dragPasteboardBaseline else { break }
                isDragging = true
                onDragSessionChange?(true)
            }
            onDragMoved?(NSEvent.mouseLocation)
        case .leftMouseUp:
            if isDragging {
                isDragging = false
                onDragSessionChange?(false)
            }
        default:
            break
        }
    }
}
