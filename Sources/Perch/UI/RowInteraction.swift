import AppKit
import Combine
import CoreGraphics
import Foundation

struct TransformPlaceholder: Identifiable, Equatable {
    enum State: Equatable {
        case pending
        case failed(String)
    }

    let id: UUID
    let sourceItemID: UUID
    let title: String
    let replacesSource: Bool
    var state: State

    init(
        id: UUID,
        sourceItemID: UUID,
        title: String,
        replacesSource: Bool = false,
        state: State
    ) {
        self.id = id
        self.sourceItemID = sourceItemID
        self.title = title
        self.replacesSource = replacesSource
        self.state = state
    }

    var isPendingReplacement: Bool {
        guard replacesSource else { return false }
        if case .pending = state { return true }
        return false
    }
}

enum ShelfDisplayEntryID: Hashable {
    case item(UUID)
    case transform(UUID)
}

enum ShelfDisplayEntry: Identifiable {
    case item(StoredItem)
    case transform(TransformPlaceholder)

    var id: ShelfDisplayEntryID {
        switch self {
        case let .item(item): return .item(item.id)
        case let .transform(placeholder):
            return placeholder.isPendingReplacement
                ? .item(placeholder.sourceItemID)
                : .transform(placeholder.id)
        }
    }
}

/// Which row the pointer is currently over. Updated by `ShelfHostView`'s AppKit
/// mouse-tracking (the SwiftUI content never receives mouse events, since the host
/// view intercepts hit-testing) and observed by the SwiftUI rows to show the hover
/// highlight + delete button.
@MainActor
final class RowInteractionState: ObservableObject {
    @Published var hoveredItemID: UUID?
    /// The recent-arrival ghost row under the pointer (its offer id), or nil.
    @Published var hoveredArrivalID: String?
    /// Rows selected for a multi-item action.
    @Published private(set) var selectedItemIDs: Set<UUID> = []
    private var selectionPolicy = ShelfSelectionPolicy<UUID>()

    /// Items currently being dragged to reorder (lifted styling).
    @Published var draggingItemIDs: Set<UUID> = []

    /// The item mid-delete: its row does a quick affirmative pop (slight scale-up) before
    /// shrinking away. Set for ~110ms between the click and the actual removal.
    @Published var deletingItemIDs: Set<UUID> = []

    /// Items participating in a move-mode system drag. Their source rows remain in place
    /// with lifted styling until the drop resolves, avoiding an empty-card flash.
    @Published var vendingItemIDs: Set<UUID> = []
    /// Transform rows are presentation-only and never enter ItemStore or index.json.
    @Published private(set) var transformPlaceholders: [TransformPlaceholder] = []
    @Published private(set) var transformResultDetails: [UUID: String] = [:]
    private var transformResultClearTasks: [UUID: Task<Void, Never>] = [:]
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

    /// True while the pointer is over the card's grab handle (or a handle drag is in
    /// flight), so the grabber brightens to advertise that it moves the whole card.
    @Published var isGrabberHovered = false

    /// True while the pointer is anywhere over the card. A movable card keeps a stable
    /// handle reveal in sync with the panel's live resize.
    @Published var isCardHovered = false

    /// Live 0...1 progress of the handle lane. The controller derives this from the
    /// panel's actual animated height so each point added above is consumed by the lane,
    /// leaving the shelf body and rows pixel-stationary.
    @Published var grabberRevealProgress: CGFloat = 0

    /// True while the shelf is free-floating (torn off an edge or cursor-summoned).
    /// A free card remains movable regardless of the docked "Dragging Enabled" toggle,
    /// but its handle is still only revealed on hover.
    @Published var isFreeFloating = false

    /// True while a free-floating shelf is locked in place: the grab handle hides and
    /// whole-card drags are refused until it's unlocked or closed.
    @Published var isLockedInPlace = false

    func clickSelection(
        _ itemID: UUID,
        modifier: ShelfSelectionPolicy<UUID>.Modifier,
        orderedItemIDs: [UUID]
    ) {
        selectionPolicy.click(itemID, modifier: modifier, orderedItemIDs: orderedItemIDs)
        selectedItemIDs = selectionPolicy.selectedItemIDs
    }

    func contextClickSelection(_ itemID: UUID) {
        selectionPolicy.contextClick(itemID)
        selectedItemIDs = selectionPolicy.selectedItemIDs
    }

    func replaceSelection(_ itemIDs: Set<UUID>, anchorItemID: UUID? = nil) {
        selectionPolicy.replaceSelection(itemIDs, anchorItemID: anchorItemID)
        selectedItemIDs = selectionPolicy.selectedItemIDs
    }

    func removeFromSelection(_ itemIDs: Set<UUID>) {
        selectionPolicy.removeFromSelection(itemIDs)
        selectedItemIDs = selectionPolicy.selectedItemIDs
    }

    func clearSelection() {
        selectionPolicy.clearSelection()
        selectedItemIDs = selectionPolicy.selectedItemIDs
    }

    func addTransformPlaceholder(_ placeholder: TransformPlaceholder) {
        transformPlaceholders.append(placeholder)
    }

    func failTransformPlaceholder(_ id: UUID, message: String) {
        guard let index = transformPlaceholders.firstIndex(where: { $0.id == id }) else {
            return
        }
        transformPlaceholders[index].state = .failed(message)
    }

    func removeTransformPlaceholder(_ id: UUID) {
        transformPlaceholders.removeAll { $0.id == id }
    }

    func clearTransformPlaceholders() {
        transformPlaceholders.removeAll()
    }

    func dismissTransformFailures() {
        transformPlaceholders.removeAll {
            if case .failed = $0.state { return true }
            return false
        }
    }

    func showTransformResultDetail(_ detail: String, for itemID: UUID) {
        transformResultDetails[itemID] = detail
        transformResultClearTasks[itemID]?.cancel()
        transformResultClearTasks[itemID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.transformResultDetails[itemID] = nil
            self?.transformResultClearTasks[itemID] = nil
        }
    }

    func clearTransformResultDetails() {
        for task in transformResultClearTasks.values { task.cancel() }
        transformResultClearTasks.removeAll()
        transformResultDetails.removeAll()
    }

    func displayEntries(for items: [StoredItem]) -> [ShelfDisplayEntry] {
        let itemIDs = Set(items.map(\.id))
        var entries: [ShelfDisplayEntry] = []
        for item in items {
            let placeholders = transformPlaceholders.filter { $0.sourceItemID == item.id }
            if let replacement = placeholders.first(where: \.isPendingReplacement) {
                entries.append(.transform(replacement))
                entries.append(contentsOf: placeholders
                    .filter { $0.id != replacement.id }
                    .map(ShelfDisplayEntry.transform))
            } else {
                entries.append(.item(item))
                entries.append(contentsOf: placeholders.map(ShelfDisplayEntry.transform))
            }
        }
        entries.append(contentsOf: transformPlaceholders
            .filter { !itemIDs.contains($0.sourceItemID) }
            .map(ShelfDisplayEntry.transform))
        return entries
    }
}

/// Delete-button layout constants shared between the SwiftUI rendering (`ItemRowView`)
/// and the AppKit hit-testing (`ShelfHostView`) so the drawn button and its clickable
/// rect line up. Row height/spacing/padding live on `ShelfTheme`.
enum RowMetrics {
    /// Horizontal breathing room inside a labeled item chip.
    static let labeledRowHorizontalPadding: CGFloat = 10
    /// Gap between the file preview and its label.
    static let labeledRowSpacing: CGFloat = 10
    /// Delete button diameter.
    static let deleteDiameter: CGFloat = 20
    /// Trailing inset of the delete button from the row's right edge.
    static let deleteTrailingInset: CGFloat = 7
    /// Gap between the two trailing buttons when a row also offers a learned route.
    static let trailingActionSpacing: CGFloat = 4

    /// Distance from the row's trailing edge to the center of trailing button
    /// `index` (0 is the outermost — the delete button). Shared by the SwiftUI
    /// rendering and the AppKit hit math.
    static func trailingActionCenterInset(index: Int) -> CGFloat {
        deleteTrailingInset
            + deleteDiameter / 2
            + CGFloat(index) * (deleteDiameter + trailingActionSpacing)
    }
    /// Total height of the grab-handle strip drawn above the rows when the shelf holds
    /// items. Part of the row-geometry contract: the SwiftUI layout, the AppKit hit
    /// math, and the controller's height estimate all include it.
    static let grabberZoneHeight: CGFloat = 16
    /// Size of the grabber capsule itself, centered in the zone.
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    /// Height of the empty shelf's drop tile. Shared by SwiftUI layout and AppKit's
    /// window-size estimate.
    static let emptyTileHeight: CGFloat = 64
    /// A labeled item is a compact chip instead of a bar spanning the row lane. The
    /// width follows its visible title, remains capped by the available lane, and only
    /// grows enough to hold the trailing action while that action is visible.
    static func itemRowWidth(
        title: String,
        theme: ShelfTheme,
        showsLabels: Bool,
        showsAction: Bool,
        showsRouteAction: Bool = false,
        maximumWidth: CGFloat
    ) -> CGFloat {
        let boundedMaximum = max(0, maximumWidth)
        guard showsLabels else { return boundedMaximum }

        let fontWeight: NSFont.Weight = theme.style == .glass ? .medium : .regular
        let font = NSFont.systemFont(ofSize: theme.titleSize, weight: fontWeight)
        let titleWidth = ceil(
            (title as NSString).size(withAttributes: [.font: font]).width
        )
        // The route button is only drawn on hover, but its room is reserved the whole
        // time: a card that widened under the pointer would shift every other row. A
        // theme with no trailing actions at all keeps none of this space.
        var actionWidth: CGFloat = 0
        if showsAction {
            actionWidth = deleteDiameter + deleteTrailingInset
            if showsRouteAction {
                actionWidth += deleteDiameter + trailingActionSpacing
            }
        }
        let desiredWidth =
            labeledRowHorizontalPadding * 2
            + theme.iconSize
            + labeledRowSpacing
            + titleWidth
            + actionWidth
        return min(boundedMaximum, desiredWidth)
    }

    /// Width of a populated card whose rows hug their titles. The user's Width setting
    /// supplies `maximumWidth`; it is a truncation ceiling, not forced empty space.
    static func contentHuggingCardWidth(
        rows: [(title: String, showsAction: Bool, showsRouteAction: Bool)],
        theme: ShelfTheme,
        maximumWidth: CGFloat
    ) -> CGFloat {
        let boundedMaximum = max(0, maximumWidth)
        let maximumRowWidth = max(
            0,
            boundedMaximum - theme.contentPadding * 2
        )
        let widestRow = rows.map {
            itemRowWidth(
                title: $0.title,
                theme: theme,
                showsLabels: true,
                showsAction: $0.showsAction,
                showsRouteAction: $0.showsRouteAction,
                maximumWidth: maximumRowWidth
            )
        }.max() ?? 0
        return min(
            boundedMaximum,
            widestRow + theme.contentPadding * 2
        )
    }

    /// Keep rows at the width they have at the standard (100%) card size when the
    /// card itself is widened. The extra width belongs to the card as breathing room,
    /// rather than stretching every entry into a long bar. Cards narrower than the
    /// standard size still give rows all available room so content never clips.
    static func rowLaneWidth(availableWidth: CGFloat, widthScale: CGFloat) -> CGFloat {
        availableWidth / max(widthScale, 1)
    }

    /// Horizontal inset that centers the standard-width row lane in a widened card.
    /// Shared by SwiftUI layout and AppKit row/delete/arrival hit-testing.
    static func rowLaneInset(availableWidth: CGFloat, widthScale: CGFloat) -> CGFloat {
        max(0, (availableWidth - rowLaneWidth(
            availableWidth: availableWidth,
            widthScale: widthScale
        )) / 2)
    }

    /// Square preview size in deck mode. It fills the standard-width row lane while
    /// staying inside the card's existing body height, leaving the outer shelf frame
    /// untouched.
    static func stackedPreviewSide(
        availableWidth: CGFloat,
        widthScale: CGFloat,
        availableHeight: CGFloat,
        contentPadding: CGFloat
    ) -> CGFloat {
        min(
            rowLaneWidth(availableWidth: availableWidth, widthScale: widthScale),
            max(0, availableHeight - contentPadding * 2)
        )
    }

    /// Vertical distance between the leading edges of cards in deck mode. A fraction
    /// of each card remains exposed even when there is ample room, preserving the deck
    /// appearance; when space is tight, cards overlap further instead of growing the
    /// window.
    static func stackedRowPitch(
        availableHeight: CGFloat,
        rowCount: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        contentPadding: CGFloat
    ) -> CGFloat {
        guard rowCount > 1 else { return 0 }
        let usableHeight = max(rowHeight, availableHeight - contentPadding * 2)
        let deckPitch = min(rowHeight + rowSpacing, max(8, rowHeight * 0.32))
        return min(
            deckPitch,
            max(0, (usableHeight - rowHeight) / CGFloat(rowCount - 1))
        )
    }

    static func stackedContentHeight(
        rowCount: Int,
        rowHeight: CGFloat,
        pitch: CGFloat,
        contentPadding: CGFloat
    ) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return contentPadding * 2 + rowHeight + CGFloat(rowCount - 1) * pitch
    }
}
