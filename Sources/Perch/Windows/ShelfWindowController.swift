import AppKit
import QuartzCore

/// Reveals / hides / animates the shelf panel and persists its frame.
///
/// Hover-revealed edge shelves fade in/out in place (the window lands on its final
/// frame and only alpha animates); drag reveals slide in from the originating edge;
/// the cursor-summoned shelf adds a small center-scale pop.
@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    private static let persistedFrameKey = "Perch.ShelfWindowController.frame"
    private static let transformKey = "perch.reveal.transform"

    private static let revealDuration: CFTimeInterval = 0.30
    private static let hideDuration: CFTimeInterval = 0.18
    /// Smooth quint-style decel for the entrance; a gentle ease-in for the exit.
    private static let revealCurve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    private static let hideCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 0.2)
    /// How far the content travels during a sliding (drag) reveal, in points.
    private static let travel: CGFloat = 16
    /// How small the content starts before settling to full size on a sliding reveal.
    private static let startScale: CGFloat = 0.97
    /// A slightly punchier scale for the cursor-summon pop (no directional travel).
    private static let freeStartScale: CGFloat = 0.9

    private var revealedFrame: NSRect
    /// Invalidates completion of an older frame animation when a newer resize wins.
    /// AppKit can let an already-running `animator().setFrame` reach its old target even
    /// after a direct resize, so stale completions must restore the newest target.
    private var resizeGeneration: UInt = 0
    /// The generation of the newest *animated* resize still in flight, if any. A stale
    /// completion must only reassert the target when no newer animation is running —
    /// otherwise it snaps the window to the final frame mid-animation (two removals in
    /// quick succession made the second shrink visibly teleport).
    private var animatingResizeGeneration: UInt?
    /// Invalidates a hide completion when a newer reveal wins. Without this, opening
    /// the shelf while its fade-out is still finishing can leave AppKit reporting a
    /// visible panel whose stale completion has nevertheless ordered it out.
    private var visibilityGeneration: UInt = 0
    private var edge: ShelfEdge = .right
    /// When true, hide scales about the card's center (the cursor-summoned shelf's pop).
    var usesFreeAnimation = false

    init(panel: ShelfPanel) {
        self.panel = panel
        revealedFrame = panel.frame
    }

    func reveal(animated: Bool) {
        reveal(animated: animated, targetFrame: revealedFrame, edge: edge)
    }

    /// Reassert the model presentation of a panel that AppKit already calls visible.
    /// `isVisible` alone is not a sufficient invariant: a superseded fade/menu-tracking
    /// sequence can leave the window ordered or rendered inconsistently while the flag
    /// remains true. This is intentionally frame-neutral so a correctly positioned
    /// free shelf is never moved by a recovery check.
    func ensurePresented() {
        visibilityGeneration &+= 1
        panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        healContentViewShear()
    }

    /// Reveal at a specific frame. The window lands at `targetFrame` immediately; the
    /// content fades in in place, or — when `slides` (drag reveals) — eases in from a
    /// small offset toward the originating edge.
    func reveal(animated: Bool, targetFrame: NSRect, edge: ShelfEdge, slides: Bool = false) {
        visibilityGeneration &+= 1
        usesFreeAnimation = false
        self.edge = edge
        revealedFrame = targetFrame
        panel.setFrame(targetFrame, display: false)
        panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)

        guard animated, let layer = panel.contentView?.layer else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        if slides {
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: Self.offsetTransform(for: edge, in: layer.bounds))
            transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            transform.duration = Self.revealDuration
            transform.timingFunction = Self.revealCurve
            layer.add(transform, forKey: Self.transformKey)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.revealDuration
            context.timingFunction = Self.revealCurve
            panel.animator().alphaValue = 1
        }
    }

    /// Reveal a cursor-summoned shelf: the window lands at `targetFrame` immediately and
    /// the content layer scales up + fades in from the card's center (no edge to slide
    /// from).
    func revealFromCursor(animated: Bool, targetFrame: NSRect) {
        visibilityGeneration &+= 1
        usesFreeAnimation = true
        revealedFrame = targetFrame
        panel.setFrame(targetFrame, display: false)

        guard animated, let layer = panel.contentView?.layer else {
            panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: Self.centerScaleTransform(in: layer.bounds))
        transform.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        transform.duration = Self.revealDuration
        transform.timingFunction = Self.revealCurve
        layer.add(transform, forKey: Self.transformKey)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.revealDuration
            context.timingFunction = Self.revealCurve
            panel.animator().alphaValue = 1
        }
    }

    func hide(animated: Bool) {
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        guard animated, let layer = panel.contentView?.layer else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        let transformKey = Self.transformKey
        // Edge shelves fade out in place; only the cursor-summoned shelf keeps its
        // center-scale pop (a scale, not a slide).
        if usesFreeAnimation {
            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            transform.toValue = NSValue(caTransform3D: Self.centerScaleTransform(in: layer.bounds))
            transform.duration = Self.hideDuration
            transform.timingFunction = Self.hideCurve
            transform.fillMode = .forwards
            transform.isRemovedOnCompletion = false
            layer.add(transform, forKey: transformKey)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.hideDuration
            context.timingFunction = Self.hideCurve
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.visibilityGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.contentView?.layer?.removeAnimation(forKey: transformKey)
            }
        }
    }

    /// Smoothly grow/shrink the visible panel to a new frame (e.g. when items are added
    /// or removed and the card should hug its contents). No-op layout if hidden.
    /// `duration`/`timing` let a caller match the window's motion to a content animation
    /// (row removals); by default it uses the standard reveal curve.
    func resize(
        to targetFrame: NSRect,
        animated: Bool = true,
        duration: CFTimeInterval = 0.26,
        timing: CAMediaTimingFunction? = nil
    ) {
        resizeGeneration &+= 1
        let generation = resizeGeneration
        revealedFrame = targetFrame
        guard panel.isVisible else {
            panel.setFrame(targetFrame, display: false)
            return
        }
        guard targetFrame != panel.frame else { return }

        guard animated else {
            panel.setFrame(targetFrame, display: true)
            healContentViewShear()
            return
        }
        animatingResizeGeneration = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing ?? Self.revealCurve
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.animatingResizeGeneration == generation {
                    self.animatingResizeGeneration = nil
                }
                if generation != self.resizeGeneration,
                   self.animatingResizeGeneration == nil,
                   self.panel.frame != self.revealedFrame {
                    // A newer resize superseded this animation, but AppKit allowed the old
                    // animation to finish at its stale frame. Reassert the current target —
                    // unless a newer animation is still traveling there itself, in which
                    // case snapping now would cut it off mid-flight.
                    self.panel.setFrame(self.revealedFrame, display: true)
                }
                self.healContentViewShear()
            }
        }
    }

    /// Re-pin the contentView to the window. A setFrame delivered during a drag
    /// session's teardown (event-tracking mode) can double-apply the height delta to
    /// the contentView through autoresizing, leaving it taller than the window —
    /// bottom-anchored, so the whole card shears upward and stays that way. The panel
    /// is borderless, so the contentView must always match the frame size exactly.
    func healContentViewShear() {
        guard let contentView = panel.contentView else { return }
        let expected = NSRect(origin: .zero, size: panel.frame.size)
        if contentView.frame != expected {
            NSLog("Perch healed contentView shear: \(NSStringFromRect(contentView.frame)) -> \(NSStringFromRect(expected))")
            contentView.frame = expected
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

    /// The content's starting transform for a sliding reveal: nudged a few points toward
    /// the originating edge and scaled down slightly about its center.
    private static func offsetTransform(for edge: ShelfEdge, in bounds: CGRect) -> CATransform3D {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        switch edge {
        case .left: dx = -travel
        case .right: dx = travel
        case .notch: dy = travel   // layer y is up; start above, settle down into place
        }

        let w = bounds.width
        let h = bounds.height
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DTranslate(t, w / 2, h / 2, 0)
        t = CATransform3DScale(t, startScale, startScale, 1)
        t = CATransform3DTranslate(t, -w / 2, -h / 2, 0)
        return t
    }

    /// A pure scale about the card's center, for the cursor-summon reveal/hide.
    private static func centerScaleTransform(in bounds: CGRect) -> CATransform3D {
        let w = bounds.width
        let h = bounds.height
        var t = CATransform3DTranslate(CATransform3DIdentity, w / 2, h / 2, 0)
        t = CATransform3DScale(t, freeStartScale, freeStartScale, 1)
        t = CATransform3DTranslate(t, -w / 2, -h / 2, 0)
        return t
    }
}
