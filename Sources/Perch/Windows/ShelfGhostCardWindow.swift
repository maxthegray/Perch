import AppKit
import SwiftUI

/// A still copy of the resting shelf card, drawn at an edge the real card isn't coming
/// out of. The first-run demonstration puts one at every other chosen edge so the user
/// sees a shelf at each of them at once, instead of a card at one edge and a bare tab at
/// the rest.
///
/// It is a picture, not a shelf: click-through, empty, holding no items, and destroyed
/// when the demonstration ends. There is exactly one real shelf and it can only be at
/// one edge at a time — copying `ShelfHostView` to make a second live card would mean a
/// second set of drop targets and Quick Look state for the sake of two seconds of
/// scene-setting. Everything the eye checks — corner radius, material, stroke, the empty
/// tray symbol, the resting frame — comes from the same theme the real card uses, so the
/// copies match it even after the user changes styles.
@MainActor
final class ShelfGhostCardWindow {
    private let panel: ShelfPanel

    init(theme: ShelfTheme, frame: NSRect) {
        panel = ShelfPanel(contentRect: frame)
        // Nothing here is reachable: a click meant for the window underneath must not be
        // eaten by a decoration, and the card these imitate is on the other side of the
        // screen anyway.
        panel.ignoresMouseEvents = true

        // Same shape as the real card's window: a layer-backed plain view holding the
        // SwiftUI host, pinned by constraints. An `NSHostingView` installed directly as
        // a borderless panel's `contentView` renders the card as a flat white plate —
        // the material never resolves against the window's transparent background.
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        let host = NSHostingView(rootView: ShelfGhostCardView(theme: theme))
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container
        panel.alphaValue = 0
    }

    /// Fade in on exactly the timing an edge reveal uses, so the copies and the real card
    /// arrive as one motion rather than as a card plus some late decoration.
    func reveal() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ShelfWindowController.revealDuration
            context.timingFunction = ShelfWindowController.revealCurve
            panel.animator().alphaValue = 1
        }
    }

    /// Retract on the hide timing, for the same reason.
    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ShelfWindowController.hideDuration
            context.timingFunction = ShelfWindowController.hideCurve
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            panel.orderOut(nil)
        }
    }
}

/// The card with nothing on it: the same background, corner, stroke, and empty-tray
/// symbol `ShelfContentView` draws when the shelf is holding nothing.
private struct ShelfGhostCardView: View {
    let theme: ShelfTheme

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.cardBackground)
            .clipShape(cardShape)
            .overlay(cardShape.stroke(theme.cardStrokeColor, lineWidth: theme.cardStrokeWidth))
    }
}
