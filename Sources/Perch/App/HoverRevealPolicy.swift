/// When brushing the screen edge with the pointer may open the shelf.
///
/// A plain hover used to arm a 180ms timer that then revealed the card unconditionally, so
/// crossing the edge on the way somewhere else was enough to drop a card under the cursor
/// — where, holding items, it stayed. Two gates now gate that path: the user can turn
/// hover reveal off outright, and an armed reveal has to still find the pointer in the
/// catch zone when its delay elapses, which is what separates a dwell from a fly-past.
/// A live recent-arrival ghost stands in for the switch: the shelf just offered
/// something, so the edge stays a way back to it for as long as the offer lasts.
enum HoverRevealPolicy {
    /// With hover reveal off, resting this long at the edge counts as asking for the
    /// shelf, the same as holding Control.
    static let restRevealDelay: Duration = .milliseconds(1500)
    /// The hover dwell before a reveal: a solid reveal waits to tell a dwell from a
    /// fly-past, a peek can come at once because it takes no clicks.
    static let solidRevealDwell: Duration = .milliseconds(180)
    static let peekRevealDwell: Duration = .milliseconds(40)
    /// How long the pointer rests on a peeking shelf before it turns solid.
    static let peekCommitDelay: Duration = .milliseconds(250)

    /// Whether this hover reveal should peek. Control and a long rest are deliberate and
    /// reveal solid; a held mouse button means the pointer is busy (a scrollbar, a text
    /// selection), so it reveals nothing at all — see `blocksPeek`.
    static func peeks(
        peekEnabled: Bool,
        revealOnHoverEnabled: Bool,
        deliberate: Bool
    ) -> Bool {
        peekEnabled && revealOnHoverEnabled && !deliberate
    }

    /// Whether a plain (non-drag) pointer entry into an edge catch zone may arm a reveal.
    static func armsReveal(
        revealOnHoverEnabled: Bool,
        hasLiveGhosts: Bool = false,
        usesEdgeDock: Bool
    ) -> Bool {
        (revealOnHoverEnabled || hasLiveGhosts) && usesEdgeDock
    }

    /// Whether an armed reveal should still fire now its delay has elapsed. Both inputs
    /// are re-read at fire time, so a pointer that has moved on — or a switch turned off
    /// during the dwell — cancels instead of revealing.
    static func completesArmedReveal(
        revealOnHoverEnabled: Bool,
        hasLiveGhosts: Bool = false,
        pointerStillInCatchZone: Bool
    ) -> Bool {
        (revealOnHoverEnabled || hasLiveGhosts) && pointerStillInCatchZone
    }
}
