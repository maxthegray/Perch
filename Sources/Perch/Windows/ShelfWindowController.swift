import AppKit

/// Reveals / hides / animates the shelf panel and persists its frame.
@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    private static let persistedFrameKey = "Perch.ShelfWindowController.frame"
    private var revealedFrame: NSRect

    init(panel: ShelfPanel) {
        self.panel = panel
        revealedFrame = panel.frame
    }

    func reveal(animated: Bool) {
        let targetFrame = revealedFrame
        panel.setFrame(hiddenFrame(for: targetFrame), display: false)
        panel.orderFrontRegardless()
        setPanelFrame(targetFrame, animated: animated)
    }

    func hide(animated: Bool) {
        if panel.isVisible {
            revealedFrame = panel.frame
            persistFrame()
        }

        let targetFrame = hiddenFrame(for: revealedFrame)
        guard animated else {
            panel.setFrame(targetFrame, display: false)
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
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

    private func setPanelFrame(_ frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func hiddenFrame(for frame: NSRect) -> NSRect {
        guard let screenFrame = screen(for: frame)?.frame else {
            return frame.offsetBy(dx: frame.width, dy: 0)
        }

        return NSRect(
            x: screenFrame.maxX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
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
