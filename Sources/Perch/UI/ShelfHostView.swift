import AppKit
import Quartz
import SwiftUI

/// AppKit host (`NSView`) for the SwiftUI shelf content, hosting `ShelfContentView`
/// via `NSHostingView`. This is the **primary** path (Decision M) for both:
///  - row drag-initiation (`mouseDragged(_:)` → owns/retains an `ItemDragSource`), and
///  - interactive controls (delete / clear-all / Quick Look — T12),
/// because a `.nonactivatingPanel` that never becomes key does not reliably deliver
/// SwiftUI gestures/controls. SwiftUI gestures are off the critical path.
final class ShelfHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate, NSMenuDelegate {
    private let store: ItemStore
    private let themeStore: ThemeStore
    private let ledger: ProvenanceLedger
    private let arrivals: RecentArrivals
    private let interaction = RowInteractionState()
    private let thumbnails = ThumbnailStore()
    private let hostingView: NSHostingView<ShelfContentView>
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?
    /// The row a context-menu action applies to (the row under the right-click).
    private var menuTargetItem: StoredItem?
    /// The temporary arrival offer under the right-click, dismissed without touching
    /// the file that remains in its original folder.
    private var menuTargetArrival: ArrivalOffer?
    /// True while the right-click context menu (or one of its submenus) is open. The
    /// controller checks this so an empty shelf doesn't retract out from under the menu
    /// when the pointer moves into a submenu outside the card.
    private(set) var isContextMenuOpen = false
    /// Set on mouse-down over a row's delete button; suppresses drag and, if the mouse
    /// is released still over the button, deletes the item.
    private var pendingDeleteItem: StoredItem?
    /// Set on mouse-down over a recent-arrival ghost row. A click adopts it in place;
    /// crossing the drag threshold adopts it and immediately begins a normal vend.
    private var pendingArrival: ArrivalOffer?
    /// The row pressed at mouse-down — a pending drag that becomes either an in-shelf
    /// reorder (pointer stays inside) or a vend-out (pointer leaves the shelf).
    private var dragItem: StoredItem?
    private var dragStartPoint: NSPoint = .zero
    /// True once a reorder is underway (rows live-shuffle a preview order).
    private var reorderActive = false
    /// Item order captured at the start of a reorder, used to recompute the preview.
    private var reorderBaseOrder: [StoredItem] = []
    /// True once the gesture has handed off to a system drag (vend); local tracking stops.
    private var vendStarted = false
    /// True while a background press is dragging the whole card (drag-to-pin).
    private var shelfDragActive = false
    /// Screen-coord anchor of the background press and the window's origin at drag
    /// start, so the card follows the cursor 1:1 in screen space.
    private var shelfDragScreenStart: NSPoint = .zero
    private var shelfDragWindowOrigin: NSPoint = .zero
    /// URLs currently fed to `QLPreviewPanel`.
    private var quickLookURLs: [URL] = []
    /// True while the shelf is free-floating (cursor-summoned or dragged off its edge).
    private var isFreeMode = false
    /// The SwiftUI content's last measured natural height, mirrored here to derive the
    /// centering offset when the card is floored taller than its content.
    private var measuredContentHeight: CGFloat = 0

    // The behavior flags below are written by the Settings window (@AppStorage on these
    // keys) and read live from UserDefaults, so a change applies on the next gesture.

    /// When true, dragging an item out leaves the original on the shelf (copy);
    /// otherwise it's removed once it lands somewhere (move — the default).
    static let vendCopiesKey = "Perch.VendCopies"
    private var vendCopies: Bool {
        UserDefaults.standard.bool(forKey: Self.vendCopiesKey)
    }

    /// When true, the shelf reveals at the nearest enabled edge the moment a drag starts,
    /// instead of waiting for the pointer to reach the edge tab. Read live by the
    /// controller's drag handlers. Default true.
    static let revealOnDragStartKey = "Perch.RevealOnDragStart"

    /// When true, shaking the cursor summons a free-floating shelf at the pointer. Read
    /// live by the controller's summon handler. Default true (the original behavior), so
    /// an unset value keeps shake-to-summon on.
    static let shakeToSummonKey = "Perch.ShakeToSummon"

    /// When true, a free-floating shelf stays where it is after its last item leaves
    /// (dragged out or deleted), showing the empty drop tile, instead of dismissing
    /// itself. Read live by the controller. Default true.
    static let keepEmptyShelfKey = "Perch.KeepEmptyShelf"

    /// Called with the SwiftUI content's measured natural height so the controller can
    /// size the window to fit.
    var onContentHeight: ((CGFloat) -> Void)?

    /// Called when the user clicks a recent-arrival ghost row; the controller moves the
    /// file onto the shelf as a real item.
    var onAdoptArrival: ((ArrivalOffer) -> StoredItem?)?

    /// Called when the user picks "Show History…"; the controller opens the window.
    var onShowHistory: (() -> Void)?

    /// Called when the user picks "Settings"; the controller opens the window.
    var onShowSettings: (() -> Void)?

    /// Called when an empty cursor-summoned tile is tapped — there are no items to remove,
    /// so a plain click dismisses the whole tile.
    var onDismissEmptyFree: (() -> Void)?

    /// Called when the user picks "Close Shelf" on a free-floating shelf; the controller
    /// dismisses it without removing any stored items.
    var onCloseFreeShelf: (() -> Void)?

    /// Called just before a delete empties the shelf. The controller hides the card
    /// first — the last row rides the fade-out — so the empty-state layout (and its
    /// resize) never flashes on screen.
    var onWillRemoveLastItem: (() -> Void)?

    /// Gate + hooks for whole-card drags (the grab handle or a background press; from an
    /// edge they tear the docked card off). The controller answers whether a card drag
    /// may start, captures the docked frame when one begins, and decides pin vs.
    /// snap-back when it ends.
    var canBeginShelfDrag: (() -> Bool)?
    var onShelfDragBegan: (() -> Void)?
    var onShelfDragEnded: (() -> Void)?

    /// Fires when the pointer enters/leaves the card. On a docked card the grab handle
    /// rides along only while hovered, so the controller re-fits the window as the
    /// strip joins/leaves the layout.
    var onCardHoverChanged: ((Bool) -> Void)?

    /// Whether the pointer is currently over the card. The controller's height
    /// estimate reads this so it agrees with the layout's hover-only grab handle.
    var isCardHovered: Bool { interaction.isCardHovered }

    init(store: ItemStore, themeStore: ThemeStore, ledger: ProvenanceLedger, arrivals: RecentArrivals) {
        self.store = store
        self.themeStore = themeStore
        self.ledger = ledger
        self.arrivals = arrivals
        hostingView = NSHostingView(
            rootView: ShelfContentView(
                store: store,
                themeStore: themeStore,
                interaction: interaction,
                thumbnails: thumbnails,
                ledger: ledger,
                arrivals: arrivals
            )
        )
        super.init(frame: .zero)

        // The window is sized by the controller (from the measured content height), so
        // the hosting view must never impose its own size. Left at the default, its
        // min/intrinsic size constraints fight the manual setFrame — a drop landing
        // mid-drag resolves that fight by growing the *content view* past the window
        // (one row too tall, bottom-anchored), which shears the whole card upward.
        hostingView.sizingOptions = []

        // Pin the SwiftUI host to fill us exactly (no autoresizing-from-zero drift).
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Rebuild the root view with a height callback now that `self` exists.
        hostingView.rootView = makeRootView()
    }

    private func makeRootView() -> ShelfContentView {
        ShelfContentView(
            store: store,
            themeStore: themeStore,
            interaction: interaction,
            thumbnails: thumbnails,
            ledger: ledger,
            arrivals: arrivals,
            onContentHeight: { [weak self] height in
                self?.measuredContentHeight = height
                self?.onContentHeight?(height)
            }
        )
    }

    /// Toggle free-floating behavior (click-to-dismiss when empty, "Close Shelf" in the
    /// context menu, an always-on grab handle). Mirrored into the interaction state so
    /// the SwiftUI side shows/hides the bar to match.
    func setFreeMode(_ free: Bool) {
        isFreeMode = free
        interaction.isFreeFloating = free
    }

    /// The controller owns the lock; this mirrors it into the interaction state so the
    /// bar hides while locked and the hit-testing (`hasGrabber`) agrees.
    func setLockedInPlace(_ locked: Bool) {
        interaction.isLockedInPlace = locked
    }

    /// Called when the user toggles "Lock Position" on a free-floating shelf.
    var onToggleLock: (() -> Void)?

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    /// Guards against the scroll view bouncing an unconsumed event back up the responder
    /// chain into this override (which would recurse forever).
    private var forwardingScroll = false

    /// `hitTest` intercepts all events, so hand scrolls to the hosted SwiftUI content —
    /// otherwise the overflow ScrollView (list taller than the screen) can never scroll.
    /// Only when the content actually overflows: scrolling a fitting list would just
    /// rubber-band and can leave a stuck offset.
    override func scrollWheel(with event: NSEvent) {
        guard !forwardingScroll,
              let scrollView = enclosedScrollView(),
              let document = scrollView.documentView,
              document.frame.height > scrollView.contentView.bounds.height + 0.5
        else { return }
        forwardingScroll = true
        scrollView.scrollWheel(with: event)
        forwardingScroll = false
    }

    /// Reset a stuck scroll offset. The ScrollView is purely an overflow safety net; in
    /// the normal case the window hugs the content and there is nothing to scroll. But a
    /// drop landing mid-drag runs in the drag's event-tracking runloop mode, where the
    /// window resize is deferred — for a beat the grown content overflows the old
    /// viewport, the clip view anchors to the bottom, and the leftover offset never
    /// re-clamps once the window catches up. The result: rows shifted up out the top of
    /// the card and a blank band at the bottom. Whenever the content fits, force the
    /// offset back to the top.
    func clampScrollToTopIfContentFits() {
        guard let scrollView = enclosedScrollView(),
              let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        guard document.frame.height <= clip.bounds.height + 0.5,
              abs(clip.bounds.origin.y) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Hover tracking (drives the SwiftUI hover highlight + delete button)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        setCardHovered(true)
    }

    override func mouseMoved(with event: NSEvent) {
        // Also asserted here: when the card slides open under a stationary pointer the
        // entered event can be missed, but the first twitch lands a mouseMoved.
        setCardHovered(true)
        let point = convert(event.locationInWindow, from: nil)
        interaction.hoveredItemID = item(at: point)?.id
        interaction.hoveredArrivalID = arrivalIndex(at: point).map { ghostOffers[$0].id }
        updateGrabberHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        interaction.hoveredItemID = nil
        interaction.hoveredArrivalID = nil
        guard !shelfDragActive else { return }
        setCardHovered(false)
        if interaction.isGrabberHovered {
            interaction.isGrabberHovered = false
            NSCursor.arrow.set()
        }
    }

    /// Update the card-hover flag and tell the controller, which resizes the docked
    /// window as the grab-handle strip fades in/out with the pointer.
    private func setCardHovered(_ hovered: Bool) {
        guard interaction.isCardHovered != hovered else { return }
        interaction.isCardHovered = hovered
        onCardHoverChanged?(hovered)
    }

    /// Highlight the grab handle under the pointer and match the cursor to it: open
    /// hand over the handle, closed hand while a card drag is in flight.
    private func updateGrabberHover(at point: NSPoint) {
        let over = shelfDragActive || grabberZoneContains(point)
        if interaction.isGrabberHovered != over {
            interaction.isGrabberHovered = over
        }
        if shelfDragActive {
            NSCursor.closedHand.set()
        } else if over {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Delete button + row drag

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        resetDragState()

        if themeStore.theme.showsDeleteButton, themeStore.showsLabels,
           let index = rowIndex(at: point),
           deleteHitRect(forRow: index).contains(point) {
            pendingDeleteItem = visibleItems[index]
            return
        }

        // A press on a ghost row arms either a click-to-adopt or drag-to-vend. It must
        // not fall through to the empty-tile dismissal or whole-card drag.
        if let ghostIndex = arrivalIndex(at: point) {
            pendingArrival = ghostOffers[ghostIndex]
            dragStartPoint = point
            return
        }

        dragItem = item(at: point)
        if let item = dragItem {
            if event.modifierFlags.contains(.shift) {
                if interaction.selectedItemIDs.contains(item.id) {
                    interaction.selectedItemIDs.remove(item.id)
                    dragItem = nil
                } else {
                    interaction.selectedItemIDs.insert(item.id)
                }
            } else {
                // A normal press acts on this row without selecting it. Selection is
                // reserved for explicit Shift-click batches.
                interaction.selectedItemIDs.removeAll()
            }
        } else {
            interaction.selectedItemIDs.removeAll()
        }
        dragStartPoint = point
        shelfDragScreenStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        if let offer = pendingArrival {
            let point = convert(event.locationInWindow, from: nil)
            let moved = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            guard moved >= 4 else { return }
            pendingArrival = nil
            guard let item = onAdoptArrival?(offer) else {
                resetDragState()
                return
            }
            dragItem = item
            startVend(item, event: event)
            return
        }

        // A press that started on a delete button must not turn into a drag.
        guard pendingDeleteItem == nil, !vendStarted else { return }
        guard let item = dragItem else {
            // The press landed on the card's background (padding, row gaps, or the
            // empty tile) — a drag there moves the whole card (drag-to-pin).
            trackShelfDrag()
            return
        }
        let point = convert(event.locationInWindow, from: nil)

        if !reorderActive {
            let moved = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            guard moved >= 4 else { return }
            // Stay inside the shelf → reorder; leave it → vend out to another app.
            if bounds.contains(point) {
                beginReorder(item)
            } else {
                startVend(item, event: event)
                return
            }
        }

        if !bounds.contains(point) {
            cancelReorder()
            startVend(item, event: event)
            return
        }
        updateReorderPreview(of: item, at: point)
    }

    override func mouseUp(with event: NSEvent) {
        if let offer = pendingArrival {
            pendingArrival = nil
            let point = convert(event.locationInWindow, from: nil)
            if hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y) < 6,
               let index = arrivalIndex(at: point),
               ghostOffers[index].id == offer.id {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                _ = onAdoptArrival?(offer)
            }
            resetDragState()
            return
        }
        if let item = pendingDeleteItem {
            pendingDeleteItem = nil
            let point = convert(event.locationInWindow, from: nil)
            if let index = rowIndex(at: point),
               index < visibleItems.count,
               visibleItems[index].id == item.id,
               deleteHitRect(forRow: index).contains(point) {
                // The ✕ puts the file back where it came from (right-click ▸ Delete
                // removes it for good).
                removeWithBounce(actionItems(for: item), returnToOrigin: true)
            }
        } else if reorderActive {
            commitReorder()
        } else if shelfDragActive {
            onShelfDragEnded?()
        } else if isFreeMode, store.items.isEmpty {
            // A plain tap (no drag) on the empty tile body dismisses it — but not on
            // the grab handle, which is a drag affordance, not a close button.
            let point = convert(event.locationInWindow, from: nil)
            if hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y) < 6,
               !grabberZoneContains(point) {
                onDismissEmptyFree?()
            }
        }
        resetDragState()
        updateGrabberHover(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: Reorder / vend

    private func beginReorder(_ item: StoredItem) {
        reorderActive = true
        reorderBaseOrder = store.items
        interaction.draggingItemID = item.id
        interaction.previewOrder = store.items
    }

    /// Recompute the previewed order so `item` sits in the slot under the pointer.
    private func updateReorderPreview(of item: StoredItem, at point: NSPoint) {
        let count = reorderBaseOrder.count
        guard count > 1 else { return }
        let theme = themeStore.theme
        let pitch = theme.rowHeight + theme.rowSpacing
        let raw = Int((point.y - contentTopOffset + contentScrollOffsetY() - rowsTopInset) / pitch)
        let target = max(0, min(count - 1, raw))

        var order = reorderBaseOrder.filter { $0.id != item.id }
        order.insert(item, at: min(target, order.count))
        interaction.previewOrder = order
    }

    private func commitReorder() {
        if let order = interaction.previewOrder {
            store.setOrder(order)
        }
        cancelReorder()
    }

    private func cancelReorder() {
        reorderActive = false
        reorderBaseOrder = []
        interaction.draggingItemID = nil
        interaction.previewOrder = nil
    }

    private func startVend(_ item: StoredItem, event: NSEvent) {
        vendStarted = true
        let items = interaction.selectedItemIDs.contains(item.id)
            ? store.items.filter { interaction.selectedItemIDs.contains($0.id) }
            : [item]
        let itemIDs = Set(items.map(\.id))
        // Move semantics: the row leaves the shelf with the drag — the item is "in the
        // cursor's hand", not cloned. If the drag ends nowhere valid, the system ghost
        // slides back and the row reappears. Copy mode keeps the original visible.
        let isMove = !vendCopies
        if isMove {
            interaction.vendingItemIDs = itemIDs
        }
        let dragSource = ItemDragSource(items: items)
        let ledger = ledger
        dragSource.recordVend = { entry in
            Task { @MainActor in ledger.record(entry) }
        }
        dragSource.onWriteFailed = { [weak self] in
            Task { @MainActor in
                NSLog("Perch multi-item vend delivery failed; restoring selection to shelf")
                for item in items { self?.store.unretire(item) }
            }
        }
        dragSource.onEnded = { [weak self] operation in
            guard let self else { return }
            self.activeDragSource = nil
            guard isMove else { return }
            if operation.isEmpty {
                // No drop landed: put the row back on its perch, exactly as it was.
                // (endedAt fires after the ghost's slide-back animation completes, so
                // the row fades in right as the ghost arrives.)
                self.interaction.vendingItemIDs.removeAll()
                return
            }
            // The item landed somewhere: retire it — the row leaves the shelf now, but
            // the backing directory stays on disk for a grace period. Destinations read
            // the vended file URL (or call in the promise) asynchronously, sometimes
            // seconds after the drop; deleting eagerly made the drop silently vanish.
            for item in items { self.store.retire(item) }
            self.interaction.vendingItemIDs.removeAll()
            self.interaction.selectedItemIDs.subtract(itemIDs)
        }
        activeDragSource = dragSource
        _ = dragSource.beginDrag(from: self, event: event)
        NSLog("Perch row drag (vend) started for \(items.count) item(s)")
    }

    /// Track a background drag of the whole card: past a small slop the window follows
    /// the cursor 1:1; the controller decides at mouse-up whether it detaches (pins as
    /// a free shelf) or snaps back to its edge.
    private func trackShelfDrag() {
        let location = NSEvent.mouseLocation
        if !shelfDragActive {
            let moved = hypot(location.x - shelfDragScreenStart.x, location.y - shelfDragScreenStart.y)
            guard moved >= 4, canBeginShelfDrag?() == true else { return }
            shelfDragActive = true
            shelfDragWindowOrigin = window?.frame.origin ?? .zero
            interaction.isGrabberHovered = hasGrabber
            NSCursor.closedHand.set()
            onShelfDragBegan?()
        }
        window?.setFrameOrigin(NSPoint(
            x: shelfDragWindowOrigin.x + (location.x - shelfDragScreenStart.x),
            y: shelfDragWindowOrigin.y + (location.y - shelfDragScreenStart.y)
        ))
    }

    private func resetDragState() {
        dragItem = nil
        pendingArrival = nil
        reorderActive = false
        vendStarted = false
        shelfDragActive = false
        reorderBaseOrder = []
        interaction.draggingItemID = nil
        interaction.previewOrder = nil
    }

    /// The items as currently rendered: a row vended out in a move-mode drag is hidden
    /// until the drag resolves, so hit-testing must skip it too.
    private var visibleItems: [StoredItem] {
        store.items.filter { !interaction.vendingItemIDs.contains($0.id) }
    }

    private func item(at point: NSPoint) -> StoredItem? {
        rowIndex(at: point).map { visibleItems[$0] }
    }

    /// Whether the card currently shows the grab handle: a free-floating card always
    /// carries it — even empty — unless locked in place (the bar is always aboard a
    /// hand-placed card); a docked card needs visible items, "Dragging Enabled" on,
    /// and the pointer over the card — the strip only rides along while hovered.
    /// Must mirror ShelfContentView's layout exactly.
    private var hasGrabber: Bool {
        if isFreeMode { return !interaction.isLockedInPlace }
        return themeStore.showsGrabHandle && !visibleItems.isEmpty && interaction.isCardHovered
    }

    /// Distance from the row stack's top to the first row: just the content padding.
    /// (The grab handle is no longer part of the stack — it pins to the window top.)
    private var rowsTopInset: CGFloat {
        themeStore.theme.contentPadding
    }

    /// Distance from the view's top to the row stack's top. The grab-handle strip pins
    /// to the window's top; below it the (padding + rows) stack is vertically centered
    /// in the remaining space, so on a card floored taller than its content (the
    /// Height slider) the rows start this far down. On a content-hugging card this
    /// collapses to just the grabber strip. `measuredContentHeight` mirrors the
    /// reported height, which includes the grabber strip — subtract it to get the
    /// centered stack's true height. Every piece of row hit-test math must add this.
    private var contentTopOffset: CGFloat {
        guard measuredContentHeight > 0 else { return 0 }
        let grabber = hasGrabber ? RowMetrics.grabberZoneHeight : 0
        let stackHeight = measuredContentHeight - grabber
        return grabber + max(0, (bounds.height - grabber - stackHeight) / 2)
    }

    /// Whether `point` (view coords) falls in the grab-handle strip pinned to the very
    /// top of a populated card, full width. The floored card's empty space elsewhere is
    /// plain background (which also drags the card, but shouldn't light up the capsule).
    private func grabberZoneContains(_ point: NSPoint) -> Bool {
        hasGrabber && bounds.contains(point) && point.y < RowMetrics.grabberZoneHeight
    }

    /// The index of the row under `point`, or nil. Mirrors ShelfContentView's layout:
    /// each row is `RowMetrics.height` tall, laid out with theme-driven spacing + outer
    /// padding. Accounts for scroll offset in the rare overflow (scrolling) case.
    private func rowIndex(at point: NSPoint) -> Int? {
        let theme = themeStore.theme
        let rowHeight = theme.rowHeight + theme.rowSpacing
        let topInset = rowsTopInset
        let contentY = point.y - contentTopOffset + contentScrollOffsetY()
        // Points above the first row (the grab handle / top padding) are not a row.
        // `Int()` truncates toward zero, so without this guard the small negative
        // fractions up there would all collapse onto row 0.
        guard contentY >= topInset else { return nil }
        let index = Int((contentY - topInset) / rowHeight)
        guard index < visibleItems.count else { return nil }
        return index
    }

    /// The clickable rect of a row's delete button, matching where ItemRowView draws it
    /// (trailing-aligned, vertically centered in the row), enlarged slightly for an
    /// easier target. Shifted by the scroll offset so it tracks the visible row.
    private func deleteHitRect(forRow index: Int) -> NSRect {
        let theme = themeStore.theme
        let rowTop = contentTopOffset + rowsTopInset + CGFloat(index) * (theme.rowHeight + theme.rowSpacing)
        return trailingButtonHitRect(rowTop: rowTop)
    }

    /// A trailing ✕ button's enlarged hit rect for a row whose top edge (pre-scroll)
    /// is `rowTop` — shared by the item rows' delete and the ghosts' dismiss.
    private func trailingButtonHitRect(rowTop: CGFloat) -> NSRect {
        let theme = themeStore.theme
        let centerY = rowTop + theme.rowHeight / 2 - contentScrollOffsetY()
        let centerX = bounds.width - theme.contentPadding
            - RowMetrics.deleteTrailingInset - RowMetrics.deleteDiameter / 2
        let hit = RowMetrics.deleteDiameter + 10
        return NSRect(x: centerX - hit / 2, y: centerY - hit / 2, width: hit, height: hit)
    }

    // MARK: Recent-arrival ghosts (hit math mirrors ShelfContentView's placements)

    /// The ghost rows as currently rendered (hidden while a system drag is in flight).
    private var ghostOffers: [ArrivalOffer] {
        arrivals.suppressed ? [] : arrivals.offers
    }

    /// The top edge (pre-scroll, view coords) of ghost row `index`. On a populated
    /// shelf the ghosts continue below the real rows; on an empty shelf they replace
    /// the drop tile and use the same outer padding as a normal row stack.
    private func ghostRowTop(_ index: Int) -> CGFloat {
        let theme = themeStore.theme
        let pitch = theme.rowHeight + theme.rowSpacing
        if store.items.isEmpty {
            return contentTopOffset + theme.contentPadding + CGFloat(index) * pitch
        }
        return contentTopOffset + rowsTopInset + CGFloat(visibleItems.count + index) * pitch
    }

    /// The index of the ghost row under `point`, or nil.
    private func arrivalIndex(at point: NSPoint) -> Int? {
        let ghosts = ghostOffers
        guard !ghosts.isEmpty else { return nil }
        let theme = themeStore.theme
        let pitch = theme.rowHeight + theme.rowSpacing
        let y = point.y + contentScrollOffsetY() - ghostRowTop(0)
        guard y >= 0 else { return nil }
        let index = Int(y / pitch)
        guard index < ghosts.count,
              y - CGFloat(index) * pitch <= theme.rowHeight else { return nil }
        return index
    }

    /// Delete with a small affirmative bounce: a haptic tick and a quick pop of the row
    /// (spring scale-up), then the actual removal shrinks it away a beat later.
    private func removeWithBounce(_ items: [StoredItem], returnToOrigin: Bool) {
        guard !items.isEmpty else { return }
        let itemIDs = Set(items.map(\.id))
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        interaction.deletingItemIDs = itemIDs
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self else { return }
            let emptiesShelf = !self.store.items.isEmpty
                && self.store.items.allSatisfy { itemIDs.contains($0.id) }
            if emptiesShelf {
                // Hide the card with the row still aboard, then swap to the empty state
                // off-screen — no flash of the empty tray between bounce and dismissal.
                self.onWillRemoveLastItem?()
                try? await Task.sleep(for: .milliseconds(200))
            }
            if returnToOrigin {
                self.store.returnToOrigin(items)
            } else {
                self.store.remove(items)
            }
            self.interaction.selectedItemIDs.subtract(itemIDs)
            self.interaction.deletingItemIDs.subtract(itemIDs)
            guard !emptiesShelf else { return }
            // The next row slides up under the stationary cursor; re-derive hover so it
            // doesn't keep pointing at the removed item until the mouse moves.
            if let window = self.window {
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                self.interaction.hoveredItemID = self.item(at: point)?.id
            }
        }
    }

    /// A row action applies to the whole selection when its target is selected;
    /// otherwise it remains a single-row action.
    private func actionItems(for target: StoredItem) -> [StoredItem] {
        guard interaction.selectedItemIDs.contains(target.id) else { return [target] }
        return store.items.filter { interaction.selectedItemIDs.contains($0.id) }
    }

    /// SwiftUI's `ScrollView` is backed by an `NSScrollView`; when the list overflows the
    /// screen and scrolls, read its content offset so the row math above stays correct.
    /// Returns 0 in the normal (non-overflowing) case.
    private func contentScrollOffsetY() -> CGFloat {
        enclosedScrollView()?.contentView.bounds.origin.y ?? 0
    }

    /// The `NSScrollView` backing the SwiftUI `ScrollView`, found by walking the hosted
    /// view tree (nil while the shelf is empty — the empty state has no scroll view).
    private func enclosedScrollView() -> NSScrollView? {
        var queue = hostingView.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Grow/shrink the empty drop target while a drag is in flight.
    func setDropTarget(_ active: Bool) {
        interaction.isDropTarget = active
    }

    /// Show/hide the accent drop-target outline — true only while a drag is actually over
    /// the shelf's drop area. Animated at the mutation site so the pop-in and the fade-out
    /// each get their own crisp curve (a blanket `.animation(value:)` leaks the springy
    /// tail onto the fade).
    func setDragOverShelf(_ over: Bool) {
        let animation: Animation = over
            ? .spring(response: 0.12, dampingFraction: 0.55)  // near-instant, slight snap
            : .easeOut(duration: 0.06)                        // immediate clean fade
        withAnimation(animation) {
            interaction.isDragOverShelf = over
        }
    }

    /// Clear any hover highlight / armed delete / in-flight reorder (called when the
    /// shelf hides so stale state doesn't carry into the next reveal).
    func resetInteraction() {
        interaction.hoveredItemID = nil
        interaction.hoveredArrivalID = nil
        interaction.isGrabberHovered = false
        // Cleared without the hover callback: the shelf is hiding, so a re-fit resize
        // would only fight the hide animation. The controller reads the live flag.
        interaction.isCardHovered = false
        interaction.selectedItemIDs.removeAll()
        interaction.deletingItemIDs.removeAll()
        pendingDeleteItem = nil
        resetDragState()
    }

    // MARK: - Context menu (AppKit; reliable while the panel is non-key)

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        menu.delegate = self

        if let ghostIndex = arrivalIndex(at: point) {
            menuTargetItem = nil
            menuTargetArrival = ghostOffers[ghostIndex]
            interaction.selectedItemIDs.removeAll()

            let dismiss = NSMenuItem(
                title: "Dismiss",
                action: #selector(dismissArrivalMenuAction(_:)),
                keyEquivalent: ""
            )
            dismiss.target = self
            menu.addItem(dismiss)
            menu.addItem(.separator())
        } else if let item = item(at: point) {
            menuTargetArrival = nil
            // A context click outside the Shift-selection targets only this row.
            if !interaction.selectedItemIDs.contains(item.id) {
                interaction.selectedItemIDs.removeAll()
            }
            menuTargetItem = item
            let targets = actionItems(for: item)

            let quickLook = NSMenuItem(
                title: targets.count > 1 ? "Quick Look \(targets.count) Items" : "Quick Look",
                action: #selector(quickLookMenuAction(_:)),
                keyEquivalent: ""
            )
            quickLook.target = self
            quickLook.isEnabled = targets.contains { !previewableURLs(for: $0).isEmpty }
            menu.addItem(quickLook)

            let delete = NSMenuItem(
                title: targets.count > 1 ? "Delete \(targets.count) Items" : "Delete",
                action: #selector(deleteMenuAction(_:)),
                keyEquivalent: ""
            )
            delete.target = self
            menu.addItem(delete)

            let returnItems = NSMenuItem(
                title: targets.count > 1 ? "Return \(targets.count) Items" : "Return",
                action: #selector(returnMenuAction(_:)),
                keyEquivalent: ""
            )
            returnItems.target = self
            menu.addItem(returnItems)

            menu.addItem(.separator())
        } else {
            menuTargetItem = nil
            menuTargetArrival = nil
            interaction.selectedItemIDs.removeAll()
        }

        let returnAll = NSMenuItem(
            title: "Return All",
            action: #selector(returnAllMenuAction(_:)),
            keyEquivalent: ""
        )
        returnAll.target = self
        returnAll.isEnabled = !store.items.isEmpty
        menu.addItem(returnAll)

        let history = NSMenuItem(
            title: "History",
            action: #selector(showHistoryAction(_:)),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        // A free-floating shelf has no ✕ — this is how it's dismissed (items stay stored).
        // "Lock Position" turns it into a fixture: the bar hides and card drags are
        // refused until it's unlocked or closed.
        if isFreeMode {
            let lock = NSMenuItem(
                title: "Lock Position",
                action: #selector(toggleLockAction(_:)),
                keyEquivalent: ""
            )
            lock.target = self
            lock.state = interaction.isLockedInPlace ? .on : .off
            menu.addItem(lock)

            let closeShelf = NSMenuItem(
                title: "Close Shelf",
                action: #selector(closeFreeShelfAction(_:)),
                keyEquivalent: ""
            )
            closeShelf.target = self
            menu.addItem(closeShelf)
        }

        // Everything configurable lives in the Settings window; the menu stays actions-only.
        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Settings",
            action: #selector(showSettingsAction(_:)),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Perch", action: #selector(quitAction(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        isContextMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isContextMenuOpen = false
    }

    @objc private func quitAction(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc private func showHistoryAction(_ sender: NSMenuItem) {
        onShowHistory?()
    }

    @objc private func showSettingsAction(_ sender: NSMenuItem) {
        onShowSettings?()
    }

    @objc private func closeFreeShelfAction(_ sender: NSMenuItem) {
        onCloseFreeShelf?()
    }

    @objc private func toggleLockAction(_ sender: NSMenuItem) {
        onToggleLock?()
    }

    @objc private func deleteMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        removeWithBounce(actionItems(for: item), returnToOrigin: false)
        menuTargetItem = nil
    }

    @objc private func returnMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        removeWithBounce(actionItems(for: item), returnToOrigin: true)
        menuTargetItem = nil
    }

    @objc private func dismissArrivalMenuAction(_ sender: NSMenuItem) {
        guard let offer = menuTargetArrival else { return }
        arrivals.dismiss(offer)
        menuTargetArrival = nil
    }

    @objc private func returnAllMenuAction(_ sender: NSMenuItem) {
        store.returnToOrigin(store.items)
        menuTargetItem = nil
    }

    @objc private func quickLookMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        presentQuickLook(for: actionItems(for: item))
    }

    // MARK: - Quick Look

    private func previewableURLs(for item: StoredItem) -> [URL] {
        item.backingFileURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func presentQuickLook(for items: [StoredItem]) {
        let urls = items.flatMap(previewableURLs)
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        quickLookURLs = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel) {
        quickLookURLs = []
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        quickLookURLs[index] as NSURL
    }
}
