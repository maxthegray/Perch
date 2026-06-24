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

    /// Fired when the user "shakes" the cursor (rapid back-and-forth) — the gesture that
    /// summons the shelf at the pointer. Carries the current cursor location.
    var onSummonAtCursor: ((NSPoint) -> Void)?

    private var monitor: Any?
    private var isDragging = false

    // Shake detector state. We watch horizontal motion and count direction reversals
    // where each preceding swipe covered enough distance to be a deliberate flick; a
    // burst of reversals inside a short window is a shake.
    private var lastShakeX: CGFloat?
    private var shakeDirection = 0
    private var shakeDirectionTravel: CGFloat = 0
    private var shakeReversalTimes: [TimeInterval] = []
    private var lastSummonTime: TimeInterval = 0
    /// Minimum distance a swipe must cover before a reversal counts (filters jitter).
    private static let shakeMinSwing: CGFloat = 35
    /// Reversals must fall within this window to count as one shake.
    private static let shakeWindow: TimeInterval = 0.45
    /// How many reversals make a shake (back→forth→back).
    private static let shakeReversalsToFire = 3
    /// Quiet period after firing so one shake doesn't summon repeatedly.
    private static let shakeCooldown: TimeInterval = 1.0

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
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
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
        case .mouseMoved:
            detectShake(at: NSEvent.mouseLocation)
        default:
            break
        }
    }

    /// Feed a cursor sample to the shake detector; fires `onSummonAtCursor` on a shake.
    private func detectShake(at point: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastShakeX = point.x }
        guard let lastX = lastShakeX else { return }

        let dx = point.x - lastX
        guard abs(dx) >= 1 else { return }
        let direction = dx > 0 ? 1 : -1

        if direction == shakeDirection {
            shakeDirectionTravel += abs(dx)
        } else {
            // A reversal only counts if the prior swing was a real flick, not jitter.
            if shakeDirectionTravel >= Self.shakeMinSwing {
                shakeReversalTimes.append(now)
            }
            shakeDirection = direction
            shakeDirectionTravel = abs(dx)
        }

        shakeReversalTimes.removeAll { now - $0 > Self.shakeWindow }
        guard shakeReversalTimes.count >= Self.shakeReversalsToFire,
              now - lastSummonTime > Self.shakeCooldown else { return }

        shakeReversalTimes.removeAll()
        lastSummonTime = now
        onSummonAtCursor?(point)
    }
}
