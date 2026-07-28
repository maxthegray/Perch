import AppKit
import SwiftUI

// MARK: - Behavior demos

/// A looping miniature scene that acts out one behavior setting inside a tiny "screen".
/// Driven by wall-clock time (`TimelineView`), so every element's position is a pure
/// function of the loop time and no animation state is kept. `flag` lets the state-aware
/// demos (keep-open, move/copy) act out whichever variant is currently selected.
struct BehaviorDemo: View {
    enum Kind {
        case shakeToSummon, revealOnDrag, keepEmpty, moveShelf, dragOut
    }

    let kind: Kind
    var flag = true

    private static let width: CGFloat = 112
    private static let height: CGFloat = 64
    /// The shelf's center x when docked at the right edge, and when slid offscreen.
    private static let shelfShownX: CGFloat = 92
    private static let shelfHiddenX: CGFloat = 130

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)
            scene(at: t)
                // Brief crossfade at the loop boundary hides every scene's reset jump.
                .opacity(min(ramp(t, 0, 0.25), 1 - ramp(t, duration - 0.25, duration)))
        }
        .frame(width: Self.width, height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private var duration: Double {
        switch kind {
        case .shakeToSummon, .moveShelf: return 4.6
        case .revealOnDrag, .keepEmpty, .dragOut: return 5.2
        }
    }

    @ViewBuilder
    private func scene(at t: Double) -> some View {
        switch kind {
        case .shakeToSummon: shakeScene(t)
        case .revealOnDrag: revealScene(t)
        case .keepEmpty: keepEmptyScene(t)
        case .moveShelf: moveShelfScene(t)
        case .dragOut: dragOutScene(t)
        }
    }

    /// Cursor wiggles in place, the shelf slides in, lingers, and slides back out.
    private func shakeScene(_ t: Double) -> some View {
        let envelope = ramp(t, 0.7, 0.9) - ramp(t, 1.5, 1.7)
        let wiggle = sin((t - 0.7) * 24) * 7 * envelope
        let shelfIn = ramp(t, 1.6, 2.0) - ramp(t, 3.7, 4.1)
        return ZStack {
            shelf(rows: [1, 1, 1], x: shelfX(shelfIn))
            cursor(x: 46 + wiggle, y: 36)
        }
    }

    /// A file gets picked up on the desktop; the shelf peeks out to catch it.
    private func revealScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.2, 0.8)
        let drag = ramp(t, 1.0, 2.6)
        let dropped = ramp(t, 2.6, 2.9)
        let shelfIn = ramp(t, 1.2, 1.6) - ramp(t, 4.2, 4.6)
        let docX = lerp(20, 78, drag)
        let docY = lerp(46, 32, drag)
        return ZStack {
            shelf(rows: [1, 1, dropped], x: shelfX(shelfIn))
            file(x: docX, y: docY, opacity: 1 - dropped)
            cursor(x: lerp(58, docX + 4, approach), y: lerp(18, docY + 4, approach))
        }
    }

    /// The only item leaves the shelf. With the flag on the empty shelf stays put;
    /// off, it slides away once the item is gone.
    private func keepEmptyScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.5, 1.1)
        let pull = ramp(t, 1.4, 2.7)
        let pickup = ramp(t, 1.4, 1.6)
        let settle = ramp(t, 3.1, 3.5)
        let shelfIn = flag ? 1 : 1 - ramp(t, 3.7, 4.2)
        let itemX = lerp(Self.shelfShownX, 32, pull)
        let itemY = lerp(30, 44, pull)
        return ZStack {
            shelf(rows: [1 - pickup], x: shelfX(shelfIn))
            file(x: itemX, y: itemY, opacity: pickup * (1 - settle))
            cursor(x: lerp(48, itemX + 4, approach), y: lerp(52, itemY + 4, approach))
        }
    }

    /// Cursor grabs the handle and pulls the whole shelf off its edge, parking it
    /// free-floating in the middle of the screen.
    private func moveShelfScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.3, 0.9)
        let drag = ramp(t, 1.1, 2.3) - ramp(t, 3.2, 4.0)
        let shelfX = lerp(Self.shelfShownX, 46, drag)
        let shelfY = lerp(34, 30, drag)
        return ZStack {
            shelf(rows: [1, 1], x: shelfX, y: shelfY, grabber: true)
            cursor(
                x: lerp(40, shelfX, approach),
                y: lerp(18, shelfY - 15, approach)
            )
        }
    }

    /// An item is dragged off the shelf. Copy leaves the original row behind;
    /// Move takes it along.
    private func dragOutScene(_ t: Double) -> some View {
        let approach = ramp(t, 0.3, 0.9)
        let pull = ramp(t, 1.1, 2.5)
        let pickup = ramp(t, 1.1, 1.3)
        let settle = ramp(t, 3.8, 4.3)
        let topRow = flag ? 1 : 1 - pickup
        let itemX = lerp(Self.shelfShownX, 28, pull)
        let itemY = lerp(26, 44, pull)
        return ZStack {
            shelf(rows: [topRow, 1], x: shelfX(1))
            file(x: itemX, y: itemY, opacity: pickup * (1 - settle))
            cursor(x: lerp(44, itemX + 4, approach), y: lerp(52, itemY + 4, approach))
        }
    }

    // MARK: Scene elements

    private func shelfX(_ shownFraction: Double) -> CGFloat {
        lerp(Self.shelfHiddenX, Self.shelfShownX, shownFraction)
    }

    /// The miniature perch: a rounded card with capsule "rows" whose opacities the
    /// scenes animate independently.
    private func shelf(
        rows: [Double], x: CGFloat, y: CGFloat = 32, grabber: Bool = false
    ) -> some View {
        VStack(spacing: 3.5) {
            if grabber {
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 10, height: 2)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, opacity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 15, height: 6)
                    .opacity(opacity)
            }
        }
        .frame(width: 27, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .position(x: x, y: y)
    }

    private func cursor(x: CGFloat, y: CGFloat) -> some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.primary)
            .position(x: x, y: y)
    }

    private func file(x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor.opacity(0.75))
            .opacity(opacity)
            .position(x: x, y: y)
    }

    /// Smoothstep from 0 to 1 as `t` crosses `a`…`b`.
    private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard t > a else { return 0 }
        guard t < b else { return 1 }
        let x = (t - a) / (b - a)
        return x * x * (3 - 2 * x)
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: Double) -> CGFloat {
        from + (to - from) * CGFloat(fraction)
    }
}
