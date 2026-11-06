import CoreGraphics

/// A one-time hint shown on the card when the user seems to be reaching for a gesture
/// that needs a modifier.
enum GestureTip: Equatable {
    /// A plain drag on the card's background, in Control-drag mode, did nothing.
    case moveShelf
    /// An item just left the shelf in move mode.
    case keepCopy

    var key: String {
        switch self {
        case .moveShelf: return "⌃"
        case .keepCopy: return "⌥"
        }
    }

    var text: String {
        switch self {
        case .moveShelf: return "drag to move"
        case .keepCopy: return "keeps a copy"
        }
    }

    /// Each tip is shown at most once, ever.
    var shownFlagKey: String {
        switch self {
        case .moveShelf: return PerchSettings.moveShelfTipShown
        case .keepCopy: return PerchSettings.keepCopyTipShown
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
