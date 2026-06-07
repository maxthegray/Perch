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
        let screenFrame = screen.frame
        let contentRect = NSRect(
            x: screenFrame.maxX - Self.stripWidth,
            y: screenFrame.minY,
            width: Self.stripWidth,
            height: screenFrame.height
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: ShelfDropView.acceptedTypes) != nil else {
            return []
        }

        if let strip {
            strip.stripDelegate?.edgeStripDidReceiveDrag(strip)
        }
        return []
    }
}
