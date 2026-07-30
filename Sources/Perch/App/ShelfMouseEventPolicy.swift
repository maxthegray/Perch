/// Whether the shelf's windows should take mouse events at all, or be transparent to
/// them so the app underneath gets the click.
///
/// The window server hit-tests a window on its geometry alone: alpha plays no part, and a
/// fully transparent window still swallows every click inside its frame — the app below
/// never sees it. `ignoresMouseEvents` is the only thing that actually makes a window
/// transparent to the pointer, so it has to move with the shelf's visibility instead of
/// being set once when the window is built.
enum ShelfMouseEventPolicy {
    /// Where the panel is in its reveal/hide cycle. Both middle states are on screen as
    /// far as the window server is concerned, however invisible they look.
    enum PanelPhase {
        /// Ordered out: not in the hit-test tree at all.
        case hidden
        /// Ordered in at alpha 0 and fading in — present, not yet visible.
        case revealing
        case revealed
        /// Fading out toward alpha 0, still ordered in.
        case hiding
    }

    /// The panel earns the pointer once it is actually visible.
    ///
    /// The exception is a live drag session: the card is ordered in *because* something is
    /// being dragged to it, and the drop can land well inside the 0.30s fade. AppKit
    /// routes dragging-destination messages by window, so a card that ignores mouse
    /// events cannot be dropped on.
    static func panelAcceptsMouseEvents(phase: PanelPhase, dragActive: Bool) -> Bool {
        switch phase {
        case .revealed:
            return true
        case .revealing:
            return dragActive
        case .hiding, .hidden:
            return false
        }
    }

    /// The edge catch strips are invisible windows parked permanently on the screen edge,
    /// so by default they have to let the pointer through — otherwise every click on that
    /// band is eaten with nothing to show for it, in free-floating mode too, where the
    /// strips do nothing else. They need real events only while a drag is in flight, to
    /// receive `draggingEntered`. Hover is detected from the controller's global pointer
    /// samples, which need no window of their own.
    static func edgeStripAcceptsMouseEvents(dragActive: Bool) -> Bool {
        dragActive
    }
}
