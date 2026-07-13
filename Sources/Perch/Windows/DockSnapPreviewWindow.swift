import AppKit
import QuartzCore

/// A click-through ghost of the shelf's resting dock frame. It appears only while a
/// free shelf is close enough to re-dock, giving the release gesture a clear target.
@MainActor
final class DockSnapPreviewWindow: NSPanel {
    private static let echoReach: CGFloat = 24
    private let previewView = DockSnapPreviewView()
    private var targetFrame: NSRect?
    private var pullDirection = CGVector(dx: 0, dy: -1)

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        animationBehavior = .none
        previewView.wantsLayer = true
        contentView = previewView
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var canBecomeKey: Bool { false }

    func show(at frame: NSRect, cornerRadius: CGFloat, toward sourceCenter: NSPoint) {
        let dx = sourceCenter.x - frame.midX
        let dy = sourceCenter.y - frame.midY
        let length = hypot(dx, dy)
        if length > 14 {
            pullDirection = CGVector(dx: dx / length, dy: dy / length)
        }
        // Expand only toward the held shelf. Symmetric padding pushed a notch target's
        // carrier into the menu-bar region, allowing AppKit to shift the whole preview
        // even though the visible outline itself belonged below the notch.
        let leftPad = max(0, -pullDirection.dx) * Self.echoReach
        let rightPad = max(0, pullDirection.dx) * Self.echoReach
        let bottomPad = max(0, -pullDirection.dy) * Self.echoReach
        let topPad = max(0, pullDirection.dy) * Self.echoReach
        let carrierFrame = NSRect(
            x: frame.minX - leftPad,
            y: frame.minY - bottomPad,
            width: frame.width + leftPad + rightPad,
            height: frame.height + bottomPad + topPad
        )
        let localTarget = NSRect(
            x: leftPad,
            y: bottomPad,
            width: frame.width,
            height: frame.height
        )
        let localSource = NSPoint(
            x: sourceCenter.x - carrierFrame.minX,
            y: sourceCenter.y - carrierFrame.minY
        )
        if targetFrame != frame || self.frame != carrierFrame {
            targetFrame = frame
            setFrame(carrierFrame, display: true)
        }
        previewView.update(targetRect: localTarget, cornerRadius: cornerRadius, toward: localSource)
        guard !isVisible else { return }
        alphaValue = 1
        // Install the presentation animations while still hidden. Ordering the window
        // first can expose one fully-opaque frame before Core Animation takes over.
        previewView.playEntrance()
        orderFrontRegardless()
    }

    func hide() {
        guard targetFrame != nil || isVisible else { return }
        targetFrame = nil
        previewView.stopAnimations()
        orderOut(nil)
        alphaValue = 1
    }
}

private final class DockSnapPreviewView: NSView {
    private static let entranceKey = "perch.dock-preview.entrance"
    private static let echoKey = "perch.dock-preview.echo"
    private let echoLayers = (0..<3).map { _ in CAShapeLayer() }
    private var targetRect: NSRect = .zero
    private var cornerRadius: CGFloat = 18
    private var pullDirection = CGVector(dx: 0, dy: 1)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = targetRect.insetBy(dx: 2, dy: 2)
        guard rect.width > 0, rect.height > 0 else { return }

        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: max(0, cornerRadius - 2),
            yRadius: max(0, cornerRadius - 2)
        )
        // A faint dark under-stroke keeps the soft white legible over bright windows
        // without turning it into a glow or a heavy border.
        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 2.5
        path.stroke()
        NSColor.white.withAlphaComponent(0.62).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func update(targetRect: NSRect, cornerRadius: CGFloat, toward source: NSPoint) {
        self.targetRect = targetRect
        self.cornerRadius = cornerRadius
        let dx = source.x - targetRect.midX
        let dy = source.y - targetRect.midY
        let length = hypot(dx, dy)
        // Once the centers nearly coincide, tiny sub-pixel changes produce a wildly
        // rotating normalized vector. Keep the last meaningful direction instead.
        if length > 14 {
            pullDirection = CGVector(dx: dx / length, dy: dy / length)
        }
        needsDisplay = true
        updateEchoPaths()
    }

    /// One quiet settle when the target first appears. The model layer stays at rest,
    /// so hiding is immediate and can never overlap with a second fade animation.
    func playEntrance() {
        guard let layer else { return }
        layer.removeAnimation(forKey: Self.entranceKey)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1

        let scale = CABasicAnimation(keyPath: "transform.scale")
        // Start just inside the destination so the stroke never clips against its
        // borderless window while it settles into the final frame.
        scale.fromValue = 0.96
        scale.toValue = 1

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.28
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        layer.add(group, forKey: Self.entranceKey)
        startEchoAnimation()
    }

    /// Three restrained copies peel toward the held shelf. Their staggered pulse runs
    /// from the outer copy back toward the solid target, suggesting magnetic suction
    /// without drawing a connecting beam.
    private func startEchoAnimation() {
        guard let layer else { return }
        for (index, echo) in echoLayers.enumerated() where echo.superlayer == nil {
            echo.fillColor = nil
            echo.strokeColor = NSColor.white.withAlphaComponent(0.22 - CGFloat(index) * 0.045).cgColor
            echo.lineWidth = 1
            echo.opacity = 0
            layer.insertSublayer(echo, at: 0)
        }
        updateEchoPaths()
        for (index, echo) in echoLayers.enumerated() {
            echo.removeAnimation(forKey: Self.echoKey)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.22, 0.7, 0.22]
            opacity.keyTimes = [0, 0.42, 1]
            opacity.duration = 1.05
            opacity.beginTime = CACurrentMediaTime() + Double(2 - index) * 0.11
            opacity.repeatCount = .infinity
            opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            echo.add(opacity, forKey: Self.echoKey)
        }
    }

    private func updateEchoPaths() {
        guard targetRect.width > 0, targetRect.height > 0 else { return }
        // Direction changes arrive every mouse-drag event. Disable Core Animation's
        // implicit path/frame interpolation so updates track the cursor directly rather
        // than stacking quarter-second animations that wobble behind it.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (index, echo) in echoLayers.enumerated() {
            echo.frame = bounds
            let step = CGFloat(index + 1)
            let scale = 1 - step * 0.018
            let width = targetRect.width * scale
            let height = targetRect.height * scale
            let offset = step * 6
            let rect = NSRect(
                x: targetRect.midX - width / 2 + pullDirection.dx * offset,
                y: targetRect.midY - height / 2 + pullDirection.dy * offset,
                width: width,
                height: height
            ).insetBy(dx: 2, dy: 2)
            echo.path = CGPath(
                roundedRect: rect,
                cornerWidth: max(0, cornerRadius - 2 - step),
                cornerHeight: max(0, cornerRadius - 2 - step),
                transform: nil
            )
        }
    }

    func stopAnimations() {
        layer?.removeAnimation(forKey: Self.entranceKey)
        echoLayers.forEach { $0.removeAnimation(forKey: Self.echoKey) }
    }
}
