import AppKit
import QuartzCore

/// Reveals / hides / animates the shelf panel and persists its frame.
///
/// Edge shelves always fade in/out in place (the window lands on its final frame and
/// only alpha animates); the cursor-summoned shelf adds a small center-scale pop.
@MainActor
final class ShelfWindowController {
    let panel: ShelfPanel
    private static let transformKey = "perch.reveal.transform"

    // Internal rather than private so the first-run card copies (`ShelfGhostCardWindow`)
    // can move on the shelf's own timing instead of a second set of numbers that would
    // drift away from these.
    static let revealDuration: CFTimeInterval = 0.30
    static let hideDuration: CFTimeInterval = 0.18
    /// A quick dip around a live edge handoff. The panel moves only while fully
    /// transparent, so switching docks reads as a cross-fade rather than a teleport.
    private static let edgeHandoffFadeOutDuration: CFTimeInterval = 0.07
    private static let edgeHandoffFadeInDuration: CFTimeInterval = 0.11
    /// Smooth quint-style decel for the entrance; a gentle ease-in for the exit.
    static let revealCurve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    static let hideCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 0.2)
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
    /// A reveal that is still legitimately fading in. Pointer-entry and content
    /// changes can ask to "ensure" the already-visible panel during this interval; that
    /// must not remove the transform or jump alpha to one and cut the entrance short.
    private var activeRevealGeneration: UInt?
    private var edge: ShelfEdge = .right
    /// When true, hide scales about the card's center (the cursor-summoned shelf's pop).
    var usesFreeAnimation = false

    /// Where the panel is in its reveal/hide cycle, which is what decides whether it may
    /// take mouse events. Every transition below sets it, and the same generation guards
    /// that protect the animations protect this: a superseded fade's completion is
    /// dropped, so it can never leave the flag describing a state the panel has left.
    private var phase: ShelfMouseEventPolicy.PanelPhase = .hidden {
        didSet { applyMouseEventPolicy() }
    }
    var isFullyRevealed: Bool { phase == .revealed }

    /// Whether a system drag is in flight, set by the controller from its global drag
    /// state. A drag has to be able to reach the card the moment it is ordered in, since
    /// the drop routinely lands inside the fade-in.
    var dragSessionActive = false {
        didSet { applyMouseEventPolicy() }
    }

    init(panel: ShelfPanel) {
        self.panel = panel
        revealedFrame = panel.frame
        applyMouseEventPolicy()
    }

    /// A panel that looks absent must also *be* absent to the pointer. AppKit hit-tests a
    /// window on its frame and `isHidden` alone — alpha plays no part — so without this a
    /// card ordered in at alpha 0, or one whose 0.18s fade-out has not yet reached its
    /// `orderOut`, eats every click in its frame and the app below never sees them.
    private func applyMouseEventPolicy() {
        panel.ignoresMouseEvents = !ShelfMouseEventPolicy.panelAcceptsMouseEvents(
            phase: phase,
            dragActive: dragSessionActive
        )
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
        if activeRevealGeneration != nil {
            panel.orderFrontRegardless()
            return
        }
        visibilityGeneration &+= 1
        panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        phase = .revealed
        healContentViewShear()
    }

    /// Reveal at a specific frame. The window lands at `targetFrame` immediately and
    /// fades in without lateral motion, independent of which edge owns it.
    func reveal(animated: Bool, targetFrame: NSRect, edge: ShelfEdge) {
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        usesFreeAnimation = false
        self.edge = edge
        revealedFrame = targetFrame
        panel.setFrame(targetFrame, display: false)
        panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)

        guard animated else {
            activeRevealGeneration = nil
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            phase = .revealed
            return
        }

        activeRevealGeneration = generation
        panel.alphaValue = 0
        // Set before ordering in, so the window never spends a moment in the hit-test
        // tree while it is still invisible.
        phase = .revealing
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.revealDuration
            context.timingFunction = Self.revealCurve
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeRevealGeneration == generation else {
                    return
                }
                self.activeRevealGeneration = nil
                self.phase = .revealed
            }
        }
    }

    /// Reveal a cursor-summoned shelf: the window lands at `targetFrame` immediately and
    /// the content layer scales up + fades in from the card's center (no edge to slide
    /// from).
    func revealFromCursor(animated: Bool, targetFrame: NSRect) {
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        usesFreeAnimation = true
        revealedFrame = targetFrame
        panel.setFrame(targetFrame, display: false)

        guard animated, let layer = panel.contentView?.layer else {
            activeRevealGeneration = nil
            panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            phase = .revealed
            return
        }

        activeRevealGeneration = generation
        panel.alphaValue = 0
        phase = .revealing
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
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.activeRevealGeneration == generation else {
                    return
                }
                self.activeRevealGeneration = nil
                self.phase = .revealed
            }
        }
    }

    /// Cross-fade an already-visible shelf from one enabled dock to another.
    /// Repeated midpoint crossings supersede older handoffs through `visibilityGeneration`.
    func retargetAcrossEdges(to targetFrame: NSRect, edge: ShelfEdge) {
        visibilityGeneration &+= 1
        let generation = visibilityGeneration
        resizeGeneration &+= 1
        usesFreeAnimation = false
        self.edge = edge
        revealedFrame = targetFrame
        activeRevealGeneration = generation
        panel.contentView?.layer?.removeAnimation(forKey: Self.transformKey)
        phase = .revealing
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.edgeHandoffFadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.visibilityGeneration == generation else { return }
                self.panel.setFrame(targetFrame, display: false)
                self.healContentViewShear()

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.edgeHandoffFadeInDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    self.panel.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self,
                              self.visibilityGeneration == generation else { return }
                        self.activeRevealGeneration = nil
                        self.phase = .revealed
                    }
                }
            }
        }
    }

    func hide(animated: Bool) {
        visibilityGeneration &+= 1
        activeRevealGeneration = nil
        let generation = visibilityGeneration
        // The moment the retraction starts the card stops taking clicks: it is on its way
        // out, and for the whole 0.18s fade it would otherwise keep them from the app
        // that is being revealed underneath it.
        phase = animated ? .hiding : .hidden
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
                self.phase = .hidden
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
