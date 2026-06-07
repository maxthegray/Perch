import AppKit

/// Reveals / hides / animates the shelf panel and persists its frame.
@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    private static let persistedFrameKey = "Perch.ShelfWindowController.frame"
    private var revealedFrame: NSRect
    private var edge: ShelfEdge = .right

    init(panel: ShelfPanel) {
        self.panel = panel
        revealedFrame = panel.frame
    }

    func reveal(animated: Bool) {
        reveal(animated: animated, targetFrame: revealedFrame, edge: edge)
    }

    /// Reveal at a specific frame, easing + fading in from off that frame's edge
    /// (the side for left/right, the top for the notch).
    func reveal(animated: Bool, targetFrame: NSRect, edge: ShelfEdge) {
        self.edge = edge
        revealedFrame = targetFrame

        guard animated else {
            panel.alphaValue = 1
            panel.setFrame(targetFrame, display: true)
            panel.orderFrontRegardless()
            return
        }

        panel.setFrame(hiddenFrame(for: targetFrame), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide(animated: Bool) {
        let targetFrame = hiddenFrame(for: revealedFrame)
        guard animated else {
            panel.setFrame(targetFrame, display: false)
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    func restorePersistedFrame() {
        guard let frameString = UserDefaults.standard.string(forKey: Self.persistedFrameKey) else {
            revealedFrame = panel.frame
            return
        }

        let frame = NSRectFromString(frameString)
        guard frame.width > 0, frame.height > 0 else {
            revealedFrame = panel.frame
            return
        }

        revealedFrame = frame
        panel.setFrame(frame, display: false)
    }

    func persistFrame() {
        UserDefaults.standard.set(NSStringFromRect(revealedFrame), forKey: Self.persistedFrameKey)
    }

    private func hiddenFrame(for frame: NSRect) -> NSRect {
        guard let screenFrame = screen(for: frame)?.frame else {
            return frame.offsetBy(dx: frame.width, dy: 0)
        }

        switch edge {
        case .left:
            return NSRect(x: screenFrame.minX - frame.width, y: frame.minY, width: frame.width, height: frame.height)
        case .right:
            return NSRect(x: screenFrame.maxX, y: frame.minY, width: frame.width, height: frame.height)
        case .notch:
            // Slide up behind the menu bar / notch.
            return NSRect(x: frame.minX, y: screenFrame.maxY, width: frame.width, height: frame.height)
        }
    }

    private func screen(for frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        } ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}
