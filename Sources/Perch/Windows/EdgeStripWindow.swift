import AppKit
import Combine

/// Which screen edge a shelf tab / panel is attached to.
enum ShelfEdge: String, CaseIterable {
    case left
    case right
    case notch
}

/// Notified when a drag enters the edge tab (the trigger to reveal the shelf).
@MainActor
protocol EdgeStripDelegate: AnyObject {
    /// The pointer entered the tab — `viaDrag` distinguishes a drag from a hover.
    func edgeStrip(_ strip: EdgeStripWindow, pointerDidEnterViaDrag viaDrag: Bool)
    func edgeStripPointerDidExit(_ strip: EdgeStripWindow, duringDrag: Bool)
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

    /// Height of the *visible* handle pill, centered in the (taller) catch zone — a
    /// short grip that reads closer to the shelf card's size than a full-edge bar.
    static let tabVisibleHeight: CGFloat = 96

    /// Horizontal pad on each side of the notch for the traced outline.
    static let notchTracePad: CGFloat = 10

    /// Extra catch height just below the notch (so an upward drag is caught).
    static let notchCatchExtra: CGFloat = 12

    weak var stripDelegate: EdgeStripDelegate?

    /// The screen this tab is pinned to (used to reveal the shelf on the right one).
    let pinnedScreen: NSScreen

    /// Which edge of the screen this tab hugs.
    let edge: ShelfEdge

    /// Active look — the drawn handle follows it.
    let themeStore: ThemeStore

    /// Whether the visible tab is drawn. The window itself is always present (so it
    /// can catch hover + drag), but the accent handle only shows while dragging.
    var showsTab = false {
        didSet {
            guard showsTab != oldValue else { return }
            (contentView as? EdgeStripTriggerView)?.setTabVisible(showsTab)
        }
    }

    init(screen: NSScreen, edge: ShelfEdge, themeStore: ThemeStore) {
        self.pinnedScreen = screen
        self.edge = edge
        self.themeStore = themeStore
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
        // Center on the *visible* frame (minus menu bar / Dock) so the tab lines up
        // vertically with the shelf card, which is itself centered on the visible frame.
        let centerY = screen.visibleFrame.midY
        switch edge {
        case .left:
            return NSRect(x: screenFrame.minX, y: centerY - tabHeight / 2, width: stripWidth, height: tabHeight)
        case .right:
            return NSRect(x: screenFrame.maxX - stripWidth, y: centerY - tabHeight / 2, width: stripWidth, height: tabHeight)
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
    weak var strip: EdgeStripWindow? {
        didSet { observeTheme() }
    }
    private var themeCancellable: AnyCancellable?

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

    /// Redraw the handle whenever the active look changes.
    private func observeTheme() {
        themeCancellable = strip?.themeStore.$style
            .removeDuplicates()
            .sink { [weak self] _ in self?.needsDisplay = true }
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

        let theme = strip?.themeStore.theme ?? ShelfTheme.resolve(.glass)
        let accent = theme.tabAccent

        // Notch: a single flat horizontal line along the bottom edge of the notch,
        // pulled in slightly on each side so it matches the notch's visible width.
        if strip?.edge == .notch {
            let inset = EdgeStripWindow.notchTracePad + 7
            let left = bounds.minX + inset
            let right = bounds.maxX - inset
            let bottomY = bounds.minY + EdgeStripWindow.notchCatchExtra  // notch's bottom edge

            let path = NSBezierPath()
            path.move(to: NSPoint(x: left, y: bottomY))
            path.line(to: NSPoint(x: right, y: bottomY))
            path.lineWidth = theme.tabUsesGlow ? 3 : 1.5
            path.lineCapStyle = .round
            withOptionalGlow(theme.tabUsesGlow ? accent : nil) {
                accent.withAlphaComponent(theme.tabUsesGlow ? 0.95 : 0.6).setStroke()
                path.stroke()
            }
            return
        }

        // A visible handle hugging the edge: rounded on the inner side, run flush off
        // the screen edge on the outer side.
        let visibleWidth = theme.tabVisibleWidth
        let originX = strip?.edge == .left ? bounds.minX - visibleWidth : bounds.maxX - visibleWidth
        let handleHeight = min(bounds.height, EdgeStripWindow.tabVisibleHeight)
        let originY = bounds.midY - handleHeight / 2
        let barRect = NSRect(x: originX, y: originY, width: visibleWidth * 2, height: handleHeight)
        let path = NSBezierPath(
            roundedRect: barRect,
            xRadius: theme.tabCornerRadius,
            yRadius: theme.tabCornerRadius
        )

        if theme.tabUsesGlow {
            // Glass: a soft accent pill with a vertical gradient and a gentle glow.
            withOptionalGlow(accent) {
                let gradient = NSGradient(
                    colors: [accent.withAlphaComponent(0.95), accent.withAlphaComponent(0.7)]
                )
                gradient?.draw(in: path, angle: 90)
            }
        } else {
            // Minimal: a quiet, flat hairline.
            accent.withAlphaComponent(0.55).setFill()
            path.fill()
        }
    }

    /// Run `draw` with an optional soft glow shadow applied.
    private func withOptionalGlow(_ color: NSColor?, _ draw: () -> Void) {
        guard let color else {
            draw()
            return
        }
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent(0.55)
        glow.shadowBlurRadius = 8
        glow.shadowOffset = .zero
        glow.set()
        draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseEntered(with event: NSEvent) {
        if let strip {
            strip.stripDelegate?.edgeStrip(strip, pointerDidEnterViaDrag: false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let strip {
            strip.stripDelegate?.edgeStripPointerDidExit(strip, duringDrag: false)
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
            strip.stripDelegate?.edgeStripPointerDidExit(strip, duringDrag: true)
        }
    }
}
