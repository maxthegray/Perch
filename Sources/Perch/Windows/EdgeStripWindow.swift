import AppKit

/// Notified when a drag enters the edge tab (the trigger to reveal the shelf).
@MainActor
protocol EdgeStripDelegate: AnyObject {
    /// The pointer entered the tab — `viaDrag` distinguishes a drag from a hover.
    func edgeStrip(_ strip: EdgeStripWindow, pointerDidEnterViaDrag viaDrag: Bool)
    func edgeStripPointerDidExit(_ strip: EdgeStripWindow)
}

/// A small visible "drop here" tab pinned to the right screen edge, vertically
/// centered, registered for dragged types. Shown only while a drag is in progress
/// (T13) as a reminder of where to drop. It never accepts the drop itself —
/// `draggingEntered` only reveals the shelf (Decision G).
final class EdgeStripWindow: NSPanel {
    /// Tab width in points: the (mostly transparent) hover/drag catch zone.
    static let stripWidth: CGFloat = 22

    /// Tab height in points (vertically centered on the screen edge). Tall enough to
    /// be an easy drag target along the right edge.
    static let tabHeight: CGFloat = 360

    weak var stripDelegate: EdgeStripDelegate?

    /// The screen this tab is pinned to (used to reveal the shelf on the right one).
    let pinnedScreen: NSScreen

    /// Whether the visible tab is drawn. The window itself is always present (so it
    /// can catch hover + drag), but the accent handle only shows while dragging.
    var showsTab = false {
        didSet {
            guard showsTab != oldValue else { return }
            contentView?.needsDisplay = true
        }
    }

    init(screen: NSScreen) {
        self.pinnedScreen = screen
        let screenFrame = screen.frame
        let contentRect = NSRect(
            x: screenFrame.maxX - Self.stripWidth,
            y: screenFrame.midY - Self.tabHeight / 2,
            width: Self.stripWidth,
            height: Self.tabHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configureStrip()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var canBecomeKey: Bool { false }

    private func configureStrip() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false

        let triggerView = EdgeStripTriggerView(frame: NSRect(origin: .zero, size: frame.size))
        triggerView.autoresizingMask = [.width, .height]
        triggerView.strip = self
        contentView = triggerView
    }
}

private final class EdgeStripTriggerView: NSView {
    weak var strip: EdgeStripWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfDropView.acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(ShelfDropView.acceptedTypes)
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Only draw the handle while a drag is in progress.
        guard strip?.showsTab == true else { return }

        // A visible accent handle hugging the right edge: rounded on the left, run
        // flush off the screen edge on the right.
        let visibleWidth: CGFloat = 8
        let barRect = NSRect(
            x: bounds.maxX - visibleWidth,
            y: 0,
            width: visibleWidth * 2,
            height: bounds.height
        )
        let path = NSBezierPath(roundedRect: barRect, xRadius: visibleWidth, yRadius: visibleWidth)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    override func mouseEntered(with event: NSEvent) {
        if let strip {
            strip.stripDelegate?.edgeStrip(strip, pointerDidEnterViaDrag: false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let strip {
            strip.stripDelegate?.edgeStripPointerDidExit(strip)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: ShelfDropView.acceptedTypes) != nil else {
            return []
        }

        if let strip {
            strip.stripDelegate?.edgeStrip(strip, pointerDidEnterViaDrag: true)
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let strip {
            strip.stripDelegate?.edgeStripPointerDidExit(strip)
        }
    }
}
