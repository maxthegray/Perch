/// Which points on the shelf card are interactive, and which are inert background.
///
/// `ShelfHostView.hitTest` used to claim the panel's whole frame, so a press on the empty
/// space of a card floored taller than its contents — or on the side margins around the
/// row lane — was consumed with nothing to act on. The row-level math is careful not to
/// over-claim, but it only picks *which* row: by the time it ran, the outer hit test had
/// already taken the event.
///
/// Note what this does and does not buy. Declining an event stops the card acting on it;
/// it does not hand it to the app underneath, because a window that is under the pointer
/// at all owns the click unless it `ignoresMouseEvents` (see `ShelfMouseEventPolicy`).
enum ShelfHitTestPolicy {
    /// What sits under the pointer, plus the bits of gesture context that make an
    /// otherwise inert point interactive.
    struct Targets {
        /// Outside the card entirely — nothing else matters.
        var isInsideCard = false
        var isOverRow = false
        var isOverGhostRow = false
        var isOverGrabHandle = false
        /// A row's ✕ / file-it button, whose hit rect is deliberately larger than the glyph.
        var isOverTrailingButton = false
        /// Command-drag moves the whole card from anywhere on it (the alternative to the
        /// grab handle), so the held modifier makes every point draggable.
        var shelfDragModifierHeld = false
        /// Right-click (or Control-click) must still open the context menu anywhere on
        /// the card, including its empty space.
        var isContextClick = false
        /// Scrolling is routed to the hosted list. Claiming it costs nothing: a scroll
        /// the card declines is dropped rather than passed on, so declining would only
        /// break the overflow case.
        var isScrollEvent = false
        /// A free-floating shelf's empty tile is dismissed by a plain click on its body.
        var dismissesEmptyFreeShelf = false
        /// A selected batch is cleared by clicking off it, so while one exists the
        /// background is a real target instead of a click-eater.
        var hasActiveSelection = false
        /// A press this card already claimed keeps the rest of its gesture, wherever the
        /// pointer wanders.
        var gestureInFlight = false
    }

    static func claimsEvent(_ targets: Targets) -> Bool {
        guard targets.isInsideCard else { return false }
        if targets.gestureInFlight { return true }
        return targets.isOverRow
            || targets.isOverGhostRow
            || targets.isOverGrabHandle
            || targets.isOverTrailingButton
            || targets.shelfDragModifierHeld
            || targets.isContextClick
            || targets.isScrollEvent
            || targets.dismissesEmptyFreeShelf
            || targets.hasActiveSelection
    }
}
