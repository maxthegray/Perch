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

    private var monitor: Any?
    private var isDragging = false

    init() {}

    /// Install the global drag monitor. No-op if already running.
    func start() {
        guard monitor == nil else { return }

        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
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
        case .leftMouseDragged:
            if !isDragging {
                isDragging = true
                onDragSessionChange?(true)
            }
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
