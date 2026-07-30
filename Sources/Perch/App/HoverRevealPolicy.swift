/// When brushing the screen edge with the pointer may open the shelf.
///
/// A plain hover used to arm a 180ms timer that then revealed the card unconditionally, so
/// crossing the edge on the way somewhere else was enough to drop a card under the cursor
/// — where, holding items, it stayed. Two gates now gate that path: the user can turn
/// hover reveal off outright, and an armed reveal has to still find the pointer in the
/// catch zone when its delay elapses, which is what separates a dwell from a fly-past.
enum HoverRevealPolicy {
    /// Whether a plain (non-drag) pointer entry into an edge catch zone may arm a reveal.
    static func armsReveal(revealOnHoverEnabled: Bool, usesEdgeDock: Bool) -> Bool {
        revealOnHoverEnabled && usesEdgeDock
    }

    /// Whether an armed reveal should still fire now its delay has elapsed. Both inputs
    /// are re-read at fire time, so a pointer that has moved on — or a switch turned off
    /// during the dwell — cancels instead of revealing.
    static func completesArmedReveal(
        revealOnHoverEnabled: Bool,
        pointerStillInCatchZone: Bool
    ) -> Bool {
        revealOnHoverEnabled && pointerStillInCatchZone
    }
}
