import Combine
import CoreGraphics
import Foundation

/// Which row the pointer is currently over. Updated by `ShelfHostView`'s AppKit
/// mouse-tracking (the SwiftUI content never receives mouse events, since the host
/// view intercepts hit-testing) and observed by the SwiftUI rows to show the hover
/// highlight + delete button.
@MainActor
final class RowInteractionState: ObservableObject {
    @Published var hoveredItemID: UUID?

    /// The item currently being dragged to reorder (lifted styling), or nil.
    @Published var draggingItemID: UUID?

    /// The item mid-delete: its row does a quick affirmative pop (slight scale-up) before
    /// shrinking away. Set for ~110ms between the click and the actual removal.
    @Published var deletingItemID: UUID?

    /// The item currently vended out in a move-mode system drag. Its row is hidden while
    /// the drag is in flight — the item travels with the cursor instead of appearing to
    /// clone — and comes back if the drag ends nowhere valid.
    @Published var vendingItemID: UUID?
    /// While a reorder drag is in progress, the live previewed ordering the rows should
    /// render in. Nil when not reordering (rows follow the store's order).
    @Published var previewOrder: [StoredItem]?

    /// True while a system drag is in flight, so the empty drop target can grow into a
    /// larger, easier-to-hit box.
    @Published var isDropTarget = false

    /// True only while a drag is actually hovering over the shelf's drop area (not merely
    /// somewhere on screen). Drives the accent drop-target outline, so it appears the
    /// moment the item is over the shelf and disappears crisply on release.
    @Published var isDragOverShelf = false
}

/// Delete-button layout constants shared between the SwiftUI rendering (`ItemRowView`)
/// and the AppKit hit-testing (`ShelfHostView`) so the drawn button and its clickable
/// rect line up. Row height/spacing/padding live on `ShelfTheme`.
enum RowMetrics {
    /// Delete button diameter.
    static let deleteDiameter: CGFloat = 20
    /// Trailing inset of the delete button from the row's right edge.
    static let deleteTrailingInset: CGFloat = 7
}
