import AppKit

/// Which screen edge a shelf tab / panel is attached to.
enum ShelfEdge {
    case left
    case right
    case notch
}

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

    /// Horizontal pad on each side of the notch for the traced outline.
    static let notchTracePad: CGFloat = 10

    /// Extra catch height just below the notch (so an upward drag is caught).
    static let notchCatchExtra: CGFloat = 12

    weak var stripDelegate: EdgeStripDelegate?

    /// The screen this tab is pinned to (used to reveal the shelf on the right one).
    let pinnedScreen: NSScreen

    /// Which edge of the screen this tab hugs.
    let edge: ShelfEdge

    /// Whether the visible tab is drawn. The window itself is always present (so it
    /// can catch hover + drag), but the accent handle only shows while dragging.
    var showsTab = false {
        didSet {
            guard showsTab != oldValue else { return }
            (contentView as? EdgeStripTriggerView)?.setTabVisible(showsTab)
        }
    }

    init(screen: NSScreen, edge: ShelfEdge) {
        self.pinnedScreen = screen
        self.edge = edge
        let contentRect = Self.triggerFrame(for: screen, edge: edge)

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

    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// The x-range of the notch (between the menu-bar areas on either side), with a
    /// centered fallback if the auxiliary areas aren't reported.
    static func notchXInterval(for screen: NSScreen) -> (min: CGFloat, max: CGFloat) {
        let frame = screen.frame
        let leftMaxX = screen.auxiliaryTopLeftArea?.maxX ?? frame.midX - 90
        let rightMinX = screen.auxiliaryTopRightArea?.minX ?? frame.midX + 90
        return rightMinX > leftMaxX ? (leftMaxX, rightMinX) : (frame.midX - 90, frame.midX + 90)
    }

    /// The catch-zone frame for a tab on the given edge.
    static func triggerFrame(for screen: NSScreen, edge: ShelfEdge) -> NSRect {
        let screenFrame = screen.frame
        switch edge {
        case .left:
            return NSRect(x: screenFrame.minX, y: screenFrame.midY - tabHeight / 2, width: stripWidth, height: tabHeight)
        case .right:
            return NSRect(x: screenFrame.maxX - stripWidth, y: screenFrame.midY - tabHeight / 2, width: stripWidth, height: tabHeight)
        case .notch:
            let interval = notchXInterval(for: screen)
            // Cover the notch itself (up to the screen top) plus a little catch zone
            // below, so the traced outline can sit on the real notch contour.
            let triggerWidth = (interval.max - interval.min) + notchTracePad * 2
            let centerX = (interval.min + interval.max) / 2
            let height = screen.safeAreaInsets.top + notchCatchExtra
            return NSRect(x: centerX - triggerWidth / 2, y: screen.frame.maxY - height, width: triggerWidth, height: height)
        }
    }

    private func configureStrip() {
        // The notch tab must sit above the menu bar to draw on the real notch; the
        // side tabs stay at the normal floating level.
        level = edge == .notch
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            : .floating
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
        wantsLayer = true
        alphaValue = 0
        registerForDraggedTypes(ShelfDropView.acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        alphaValue = 0
        registerForDraggedTypes(ShelfDropView.acceptedTypes)
    }

    /// Fade the drawn tab in/out (events keep flowing regardless of alpha).
    func setTabVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = visible ? 1 : 0
        }
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

        // The tab is always drawn; its visibility is driven by the view's animated
        // alpha (see setTabVisible).
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()

        // Notch: trace the real notch contour — up both vertical sides to the screen
        // top, around the two rounded bottom corners.
        if strip?.edge == .notch {
            let pad = EdgeStripWindow.notchTracePad
            let cornerR: CGFloat = 10
            let left = bounds.minX + pad
            let right = bounds.maxX - pad
            let topY = bounds.maxY                              // the screen top
            let bottomY = bounds.minY + EdgeStripWindow.notchCatchExtra  // notch's bottom edge

            let path = NSBezierPath()
            path.move(to: NSPoint(x: left, y: topY))
            path.line(to: NSPoint(x: left, y: bottomY + cornerR))
            path.appendArc(
                withCenter: NSPoint(x: left + cornerR, y: bottomY + cornerR),
                radius: cornerR, startAngle: 180, endAngle: 270
            )
            path.line(to: NSPoint(x: right - cornerR, y: bottomY))
            path.appendArc(
                withCenter: NSPoint(x: right - cornerR, y: bottomY + cornerR),
                radius: cornerR, startAngle: 270, endAngle: 360
            )
            path.line(to: NSPoint(x: right, y: topY))
            path.lineWidth = 3
            path.lineCapStyle = .round
            NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
            path.stroke()
            return
        }

        // A visible accent handle hugging the edge: rounded on the inner side, run
        // flush off the screen edge on the outer side.
        let visibleWidth: CGFloat = 8
        let originX = strip?.edge == .left ? bounds.minX - visibleWidth : bounds.maxX - visibleWidth
        let barRect = NSRect(
            x: originX,
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
