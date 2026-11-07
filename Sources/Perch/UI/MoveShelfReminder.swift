import AppKit
import SwiftUI

/// When to remind someone resting on the shelf that ⌃ Control-drag moves it, and where.
enum MoveShelfReminderPolicy {
    static let hoverDelay: Duration = .seconds(3)
    static let cooldown: TimeInterval = 10 * 60
    /// Moving the shelf this many times means the gesture is known; the reminder retires.
    static let retireAfterMoves = 2
    static let gap: CGFloat = 10

    struct Context {
        var usesControlToMove: Bool
        var canMoveShelf: Bool
        var shelfMoves: Int
        var lastShown: TimeInterval?
        var now: TimeInterval
    }

    static func shouldShow(_ context: Context) -> Bool {
        guard context.usesControlToMove, context.canMoveShelf,
              context.shelfMoves < retireAfterMoves else { return false }
        guard let lastShown = context.lastShown else { return true }
        return context.now - lastShown >= cooldown
    }

    /// Beside the shelf on its open side: right of a left-docked shelf, left of a
    /// right-docked one, below the notch. A free shelf takes whichever side has room.
    static func frame(
        size: NSSize,
        beside shelf: NSRect,
        edge: ShelfEdge?,
        pointer: NSPoint,
        visible: NSRect
    ) -> NSRect {
        var origin: NSPoint
        if edge == .notch {
            origin = NSPoint(x: pointer.x - size.width / 2, y: shelf.minY - gap - size.height)
        } else {
            let right = shelf.maxX + gap
            let left = shelf.minX - gap - size.width
            let x: CGFloat
            switch edge {
            case .left: x = right
            case .right: x = left
            default: x = right + size.width <= visible.maxX ? right : left
            }
            let y = min(max(pointer.y - size.height / 2, shelf.minY), shelf.maxY - size.height)
            origin = NSPoint(x: x, y: y)
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return NSRect(origin: NSPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}

struct MoveShelfReminderView: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Hold")
            Keycap(glyph: "⌃", size: 10.5)
            Text("to drag it around")
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .padding(8)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// A click-through pill that floats beside the shelf while the pointer rests on it.
@MainActor
final class MoveShelfReminderWindow: NSPanel {
    private let hosting = NSHostingView(rootView: MoveShelfReminderView())

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
        contentView = hosting
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var canBecomeKey: Bool { false }

    func show(beside shelf: NSRect, edge: ShelfEdge?, screen: NSScreen?) {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = hosting.fittingSize
        let target = MoveShelfReminderPolicy.frame(
            size: size, beside: shelf, edge: edge, pointer: NSEvent.mouseLocation, visible: visible
        )
        let inward: CGFloat = edge == .right ? 6 : -6
        let start = edge == .notch
            ? target.offsetBy(dx: 0, dy: 6)
            : target.offsetBy(dx: inward, dy: 0)
        setFrame(start, display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        }
    }
}
