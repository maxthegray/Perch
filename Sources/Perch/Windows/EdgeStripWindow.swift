import AppKit

/// Notified when a drag enters the edge strip (the trigger to reveal the shelf).
@MainActor
protocol EdgeStripDelegate: AnyObject {
    func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow)
}

/// A persistent thin, transparent, full-height window pinned to the right screen
/// edge, registered for dragged types. It never accepts the drop — `draggingEntered`
/// only reveals the shelf (Decision G).
final class EdgeStripWindow: NSPanel {
    /// Strip width in points. Kept small to minimize idle-click capture, while
    /// `ignoresMouseEvents = false` (required to receive `draggingEntered`).
    static let stripWidth: CGFloat = 4

    weak var stripDelegate: EdgeStripDelegate?

    init(screen: NSScreen) {
        // T10: full-height, `stripWidth`-wide, pinned right edge, transparent,
        // `ignoresMouseEvents = false`, registered for dragged types.
        fatalError("unimplemented")
    }

    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }
}
