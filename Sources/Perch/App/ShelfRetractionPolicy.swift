/// One shared decision for every automatic shelf-hide path. In particular, any active
/// system drag owns a visibility hold, regardless of whether that drag originally
/// revealed the panel.
enum ShelfRetractionPolicy {
    /// Why the shelf is out, and whether the user has done anything with it since.
    enum Reveal {
        /// The pointer rested at the edge, the card appeared, and nothing has happened to
        /// it since — no drop, no click, no drag, no arriving content.
        case unusedHover
        /// Revealed deliberately (a drag, a summon, arriving content), or used since it
        /// opened.
        case used
    }

    /// Whether the shelf should retract itself now.
    ///
    /// An empty shelf has never had a reason to stay out. Beyond that, an *unused* hover
    /// reveal is undone when the pointer leaves however much sits on it: a hover is a
    /// glance, not a decision, and while a card holding items could never retract, one
    /// accidental brush past the screen edge parked a click-blocker there permanently.
    /// A shelf the user actually reached for keeps its old behavior and stays out.
    static func shouldRetractShelf(
        reveal: Reveal,
        dragActive: Bool,
        shelfDragActive: Bool,
        isFreeFloating: Bool,
        isEmpty: Bool,
        pointerInKeepAliveRegion: Bool,
        contextMenuOpen: Bool
    ) -> Bool {
        guard !dragActive,
              !shelfDragActive,
              !isFreeFloating,
              !pointerInKeepAliveRegion,
              !contextMenuOpen
        else {
            return false
        }
        return isEmpty || reveal == .unusedHover
    }
}
