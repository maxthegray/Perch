import AppKit

/// What a held modifier is about to do, shown on the shelf as motion rather than text.
enum ModifierHint: Equatable {
    case none
    /// ⌃ in Control-drag mode: the card lifts, it moves as a whole.
    case moveShelf
    /// ⌥ over an item: a copy peels out from behind it.
    case copyOut
    /// ⌘ over an item: every row grows a selection ring.
    case toggleSelection
    /// ⇧ over an item with an anchor: the range that a click would select is previewed.
    case rangeSelection
}

enum ModifierHintPolicy {
    struct Context {
        var modifiers: NSEvent.ModifierFlags = []
        /// Only ⇧ needs the pointer on an item: its range ends there. The others show
        /// whenever the shelf is up.
        var isPointerOverItem = false
        /// A reorder, vend or card drag is in progress; the gesture itself is now the
        /// feedback. A plain press is not, so ⌘-clicking keeps the rings up.
        var isInteracting = false
        var showsGrabHandle = true
        var canMoveShelf = true
        var copiesByDefault = false
        var hasSelectionAnchor = false
    }

    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    static func hint(for context: Context) -> ModifierHint {
        guard !context.isInteracting else { return .none }
        switch context.modifiers.intersection(relevant) {
        case .control:
            return !context.showsGrabHandle && context.canMoveShelf ? .moveShelf : .none
        case .option:
            return context.copiesByDefault ? .none : .copyOut
        case .command:
            return .toggleSelection
        case .shift:
            return context.isPointerOverItem && context.hasSelectionAnchor ? .rangeSelection : .none
        default:
            return .none
        }
    }

    /// Item IDs a ⇧-click on `hoveredID` would select, in shelf order.
    static func rangePreview<ID: Hashable>(
        anchor: ID?,
        hovered: ID?,
        orderedIDs: [ID]
    ) -> Set<ID> {
        guard let anchor, let hovered,
              let a = orderedIDs.firstIndex(of: anchor),
              let b = orderedIDs.firstIndex(of: hovered) else { return [] }
        return Set(orderedIDs[min(a, b)...max(a, b)])
    }

    /// Items an ⌥-drag would copy: from the hovered item, the selection when it belongs
    /// to it, otherwise just that item; with no item under the pointer, any of them.
    static func copyTargets<ID: Hashable>(hovered: ID?, selected: Set<ID>, all: [ID]) -> Set<ID> {
        guard let hovered else { return Set(all) }
        return selected.contains(hovered) ? selected : [hovered]
    }
}

/// Publishes a hint only once it has been held steadily, so quick shortcuts don't flash
/// the shelf. Clearing is immediate.
struct ModifierHintDebouncer {
    var holdDelay: TimeInterval = 0.15
    private(set) var published: ModifierHint = .none
    private var candidate: ModifierHint = .none
    private var candidateSince: TimeInterval = 0

    /// Returns the hint to display at time `now` given the currently computed `hint`.
    mutating func update(_ hint: ModifierHint, now: TimeInterval) -> ModifierHint {
        if hint == .none {
            candidate = .none
            published = .none
            return published
        }
        if hint != candidate {
            candidate = hint
            candidateSince = now
        }
        if hint != published, now - candidateSince >= holdDelay {
            published = hint
        } else if hint != published, published != .none {
            published = .none
        }
        return published
    }
}
