import CoreGraphics

/// A hint shown on the card: most once ever, when the user seems to be reaching for a
/// gesture; `controlAtEdge` each time the menu bar icon does what ⌃ could have.
enum GestureTip: Equatable {
    /// A plain drag on the card's background, in Control-drag mode, did nothing.
    case moveShelf
    /// An item just left the shelf in move mode.
    case keepCopy
    /// The menu bar icon summoned the shelf; ⌃ at this edge does the same.
    case controlAtEdge(ShelfEdge)

    var key: String? {
        switch self {
        case .moveShelf, .controlAtEdge: return "⌃"
        case .keepCopy: return "⌥"
        }
    }

    /// An SF Symbol drawn after the keycap (or alone).
    var symbol: String? {
        switch self {
        case .moveShelf, .keepCopy: return nil
        case let .controlAtEdge(edge):
            switch edge {
            case .left: return "arrow.left.to.line"
            case .right: return "arrow.right.to.line"
            case .notch: return "arrow.up.to.line"
            }
        }
    }

    var text: String? {
        switch self {
        case .moveShelf: return "drag to move"
        case .keepCopy: return "drags out a duplicate"
        case .controlAtEdge: return nil
        }
    }

    /// Set once the tip has been shown; nil for tips that repeat.
    var shownFlagKey: String? {
        switch self {
        case .moveShelf: return PerchSettings.moveShelfTipShown
        case .keepCopy: return PerchSettings.keepCopyTipShown
        case .controlAtEdge: return nil
        }
    }
}

enum GestureTipPolicy {
    /// Far enough that a sloppy click never reads as an attempt to move the card.
    static let inertDragThreshold: CGFloat = 24

    static let displayDuration: Double = 3

    /// A drag on background that the card ignored, while Control-drag is how the card
    /// moves and a move is actually allowed right now.
    static func showsMoveShelfTip(
        alreadyShown: Bool,
        showsGrabHandle: Bool,
        isPlainDrag: Bool,
        canMoveShelf: Bool,
        dragDistance: CGFloat
    ) -> Bool {
        !alreadyShown
            && !showsGrabHandle
            && isPlainDrag
            && canMoveShelf
            && dragDistance >= inertDragThreshold
    }

    /// An item really left the shelf in move mode, and the card stays on screen to show
    /// the tip. Copy-by-default makes Option a no-op, so there is nothing to teach.
    static func showsKeepCopyTip(
        alreadyShown: Bool,
        copiesByDefault: Bool,
        optionHeld: Bool,
        landedOutsidePerch: Bool,
        cardStaysVisible: Bool
    ) -> Bool {
        !alreadyShown
            && !copiesByDefault
            && !optionHeld
            && landedOutsidePerch
            && cardStaysVisible
    }
}
