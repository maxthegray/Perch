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
    private let edgeSettings: EdgeSettings
    private let ledger: ProvenanceLedger
    private let interaction = RowInteractionState()
    private let thumbnails = ThumbnailStore()
    private let loginItem = LoginItemController()
    private let hostingView: NSHostingView<ShelfContentView>
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?
    /// The row a context-menu action applies to (the row under the right-click).
    private var menuTargetItem: StoredItem?
    /// True while the right-click context menu (or one of its submenus) is open. The
    /// controller checks this so an empty shelf doesn't retract out from under the menu
    /// when the pointer moves into a submenu outside the card.
    private(set) var isContextMenuOpen = false
    /// Set on mouse-down over a row's delete button; suppresses drag and, if the mouse
    /// is released still over the button, deletes the item.
    private var pendingDeleteItem: StoredItem?
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

    /// When true, dragging an item out leaves the original on the shelf (copy);
    /// otherwise it's removed once it lands somewhere (move — the default).
    private static let vendCopiesKey = "Perch.VendCopies"
    private var vendCopies: Bool {
        get { UserDefaults.standard.bool(forKey: Self.vendCopiesKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.vendCopiesKey) }
    }

    /// When true, the shelf reveals at the nearest enabled edge the moment a drag starts,
    /// instead of waiting for the pointer to reach the edge tab. Read live by the
    /// controller's drag handlers. Default false (open on tab touch).
    static let revealOnDragStartKey = "Perch.RevealOnDragStart"
    private var revealOnDragStart: Bool {
        get { UserDefaults.standard.bool(forKey: Self.revealOnDragStartKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.revealOnDragStartKey) }
    }

    /// When true, shaking the cursor summons a free-floating shelf at the pointer. Read
    /// live by the controller's summon handler. Default true (the original behavior), so
    /// an unset value keeps shake-to-summon on.
    static let shakeToSummonKey = "Perch.ShakeToSummon"
    private var shakeToSummon: Bool {
        get { UserDefaults.standard.object(forKey: Self.shakeToSummonKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.shakeToSummonKey) }
    }

    /// Called with the SwiftUI content's measured natural height so the controller can
    /// size the window to fit.
    var onContentHeight: ((CGFloat) -> Void)?

    /// Called when the user picks "Show History…"; the controller opens the window.
    var onShowHistory: (() -> Void)?

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

    init(store: ItemStore, themeStore: ThemeStore, edgeSettings: EdgeSettings, ledger: ProvenanceLedger) {
        self.store = store
        self.themeStore = themeStore
        self.edgeSettings = edgeSettings
        self.ledger = ledger
        hostingView = NSHostingView(
            rootView: ShelfContentView(
                store: store,
                themeStore: themeStore,
                interaction: interaction,
                thumbnails: thumbnails,
                ledger: ledger
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
            onContentHeight: { [weak self] height in self?.onContentHeight?(height) }
        )
    }

    /// Toggle free-floating behavior (click-to-dismiss when empty, "Close Shelf" in the
    /// context menu). The card looks identical in both modes.
    func setFreeMode(_ free: Bool) {
        isFreeMode = free
    }

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

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        interaction.hoveredItemID = item(at: point)?.id
        updateGrabberHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        interaction.hoveredItemID = nil
        guard !shelfDragActive else { return }
        if interaction.isGrabberHovered {
            interaction.isGrabberHovered = false
            NSCursor.arrow.set()
        }
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

        dragItem = item(at: point)
        dragStartPoint = point
        shelfDragScreenStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
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
        if let item = pendingDeleteItem {
            pendingDeleteItem = nil
            let point = convert(event.locationInWindow, from: nil)
            if let index = rowIndex(at: point),
               index < visibleItems.count,
               visibleItems[index].id == item.id,
               deleteHitRect(forRow: index).contains(point) {
                // The ✕ puts the file back where it came from (right-click ▸ Delete
                // removes it for good).
                removeWithBounce(item, returnToOrigin: true)
            }
        } else if reorderActive {
            commitReorder()
        } else if shelfDragActive {
            onShelfDragEnded?()
        } else if isFreeMode, store.items.isEmpty {
            // A plain tap (no drag) on the empty tile body dismisses it.
            let point = convert(event.locationInWindow, from: nil)
            if hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y) < 6 {
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
        let raw = Int((point.y + contentScrollOffsetY() - rowsTopInset) / pitch)
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
        // Move semantics: the row leaves the shelf with the drag — the item is "in the
        // cursor's hand", not cloned. If the drag ends nowhere valid, the system ghost
        // slides back and the row reappears. Copy mode keeps the original visible.
        let isMove = !vendCopies
        if isMove {
            interaction.vendingItemID = item.id
        }
        let dragSource = ItemDragSource(item: item)
        let ledger = ledger
        dragSource.recordVend = { entry in
            Task { @MainActor in ledger.record(entry) }
        }
        dragSource.onEnded = { [weak self] operation in
            guard let self else { return }
            self.activeDragSource = nil
            guard isMove else { return }
            if operation.isEmpty {
                // No drop landed: put the row back on its perch, exactly as it was.
                // (endedAt fires after the ghost's slide-back animation completes, so
                // the row fades in right as the ghost arrives.)
                if self.interaction.vendingItemID == item.id {
                    self.interaction.vendingItemID = nil
                }
                return
            }
            // The item landed somewhere: remove it for real. Deferred briefly so any
            // in-flight file-promise write (which copies from the holding dir) can
            // finish before the dir is deleted; the row is already hidden meanwhile.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard let self else { return }
                self.store.remove(item)
                if self.interaction.vendingItemID == item.id {
                    self.interaction.vendingItemID = nil
                }
            }
        }
        activeDragSource = dragSource
        _ = dragSource.beginDrag(from: self, event: event)
        NSLog("Perch row drag (vend) started for item \(item.id.uuidString)")
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
        guard let vendingID = interaction.vendingItemID else { return store.items }
        return store.items.filter { $0.id != vendingID }
    }

    private func item(at point: NSPoint) -> StoredItem? {
        rowIndex(at: point).map { visibleItems[$0] }
    }

    /// Whether the card currently shows the grab handle above its rows (it holds visible
    /// items and the user hasn't hidden the handle). Must mirror ShelfContentView's
    /// layout exactly.
    private var hasGrabber: Bool {
        themeStore.showsGrabHandle && !visibleItems.isEmpty
    }

    /// Distance from the view's top to the first row: the content padding, plus the
    /// grab-handle strip when the card holds items.
    private var rowsTopInset: CGFloat {
        themeStore.theme.contentPadding + (hasGrabber ? RowMetrics.grabberZoneHeight : 0)
    }

    /// Whether `point` (view coords) falls in the grab-handle strip at the top of a
    /// populated card — everything above the first row, full width.
    private func grabberZoneContains(_ point: NSPoint) -> Bool {
        hasGrabber && bounds.contains(point) && point.y < rowsTopInset
    }

    /// The index of the row under `point`, or nil. Mirrors ShelfContentView's layout:
    /// each row is `RowMetrics.height` tall, laid out with theme-driven spacing + outer
    /// padding. Accounts for scroll offset in the rare overflow (scrolling) case.
    private func rowIndex(at point: NSPoint) -> Int? {
        let theme = themeStore.theme
        let rowHeight = theme.rowHeight + theme.rowSpacing
        let topInset = rowsTopInset
        let contentY = point.y + contentScrollOffsetY()
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
        let rowTop = rowsTopInset + CGFloat(index) * (theme.rowHeight + theme.rowSpacing)
        let centerY = rowTop + theme.rowHeight / 2 - contentScrollOffsetY()
        let centerX = bounds.width - theme.contentPadding
            - RowMetrics.deleteTrailingInset - RowMetrics.deleteDiameter / 2
        let hit = RowMetrics.deleteDiameter + 10
        return NSRect(x: centerX - hit / 2, y: centerY - hit / 2, width: hit, height: hit)
    }

    /// Delete with a small affirmative bounce: a haptic tick and a quick pop of the row
    /// (spring scale-up), then the actual removal shrinks it away a beat later.
    private func removeWithBounce(_ item: StoredItem, returnToOrigin: Bool) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        interaction.deletingItemID = item.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard let self else { return }
            let emptiesShelf = self.store.items.count == 1 && self.store.items.first?.id == item.id
            if emptiesShelf {
                // Hide the card with the row still aboard, then swap to the empty state
                // off-screen — no flash of the empty tray between bounce and dismissal.
                self.onWillRemoveLastItem?()
                try? await Task.sleep(for: .milliseconds(200))
            }
            if returnToOrigin {
                self.store.returnToOrigin(item)
            } else {
                self.store.remove(item)
            }
            if self.interaction.deletingItemID == item.id {
                self.interaction.deletingItemID = nil
            }
            guard !emptiesShelf else { return }
            // The next row slides up under the stationary cursor; re-derive hover so it
            // doesn't keep pointing at the removed item until the mouse moves.
            if let window = self.window {
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                self.interaction.hoveredItemID = self.item(at: point)?.id
            }
        }
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
        interaction.isGrabberHovered = false
        pendingDeleteItem = nil
        resetDragState()
    }

    // MARK: - Context menu (AppKit; reliable while the panel is non-key)

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        menu.delegate = self

        if let item = item(at: point) {
            menuTargetItem = item

            let quickLook = NSMenuItem(
                title: "Quick Look",
                action: #selector(quickLookMenuAction(_:)),
                keyEquivalent: ""
            )
            quickLook.target = self
            quickLook.isEnabled = !previewableURLs(for: item).isEmpty
            menu.addItem(quickLook)

            let delete = NSMenuItem(
                title: "Delete",
                action: #selector(deleteMenuAction(_:)),
                keyEquivalent: ""
            )
            delete.target = self
            menu.addItem(delete)

            menu.addItem(.separator())
        } else {
            menuTargetItem = nil
        }

        let clearAll = NSMenuItem(
            title: "Clear All",
            action: #selector(clearAllMenuAction(_:)),
            keyEquivalent: ""
        )
        clearAll.target = self
        clearAll.isEnabled = !store.items.isEmpty
        menu.addItem(clearAll)

        let history = NSMenuItem(
            title: "History",
            action: #selector(showHistoryAction(_:)),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        // A free-floating shelf has no ✕ — this is how it's dismissed (items stay stored).
        if isFreeMode {
            let closeShelf = NSMenuItem(
                title: "Close Shelf",
                action: #selector(closeFreeShelfAction(_:)),
                keyEquivalent: ""
            )
            closeShelf.target = self
            menu.addItem(closeShelf)
        }

        menu.addItem(.separator())
        menu.addItem(appearanceMenuItem())
        menu.addItem(dockEdgesMenuItem())
        menu.addItem(behaviorMenuItem())

        if loginItem.isAvailable {
            let launchAtLogin = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLoginAction(_:)),
                keyEquivalent: ""
            )
            launchAtLogin.target = self
            launchAtLogin.state = loginItem.isEnabled ? .on : .off
            menu.addItem(launchAtLogin)
        }

        menu.addItem(.separator())
        let versionItem = NSMenuItem(
            title: "Perch \(appVersion)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesAction(_:)),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

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

    @objc private func toggleLaunchAtLoginAction(_ sender: NSMenuItem) {
        loginItem.toggle()
    }

    @objc private func quitAction(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdatesAction(_ sender: NSMenuItem) {
        Updater.shared.checkForUpdates()
    }

    /// The bundle's marketing version, shown as a disabled menu header.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    @objc private func showHistoryAction(_ sender: NSMenuItem) {
        onShowHistory?()
    }

    @objc private func closeFreeShelfAction(_ sender: NSMenuItem) {
        onCloseFreeShelf?()
    }

    /// "Appearance ▸ Glass / Minimal / Show Names" — visual-only controls.
    private func appearanceMenuItem() -> NSMenuItem {
        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for style in ShelfStyle.allCases {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(selectStyleAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = style.rawValue
            item.state = (style == themeStore.style) ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(showNamesMenuItem())
        appearance.submenu = submenu
        return appearance
    }

    @objc private func selectStyleAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ShelfStyle(rawValue: raw) else { return }
        themeStore.style = style
    }

    /// "Dock Edges ▸ Left / Right / Top" — toggles which screen-edge docks are enabled.
    private func dockEdgesMenuItem() -> NSMenuItem {
        let edges = NSMenuItem(title: "Dock Edges", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let entries: [(String, ShelfEdge)] = [
            ("Left", .left), ("Right", .right), ("Top (Notch)", .notch)
        ]
        for (title, edge) in entries {
            let item = NSMenuItem(
                title: title,
                action: #selector(toggleEdgeAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = edge.rawValue
            item.state = edgeSettings.isEnabled(edge) ? .on : .off
            submenu.addItem(item)
        }
        edges.submenu = submenu
        return edges
    }

    @objc private func toggleEdgeAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let edge = ShelfEdge(rawValue: raw) else { return }
        edgeSettings.toggle(edge)
    }

    private func showNamesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Show Names",
            action: #selector(toggleShowLabelsAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.state = themeStore.showsLabels ? .on : .off
        return item
    }

    @objc private func toggleShowLabelsAction(_ sender: NSMenuItem) {
        themeStore.showsLabels.toggle()
    }

    private func draggingEnabledMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Dragging Enabled",
            action: #selector(toggleShowGrabHandleAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.state = themeStore.showsGrabHandle ? .on : .off
        return item
    }

    @objc private func toggleShowGrabHandleAction(_ sender: NSMenuItem) {
        themeStore.showsGrabHandle.toggle()
    }

    private func shakeToSummonMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Shake to Summon",
            action: #selector(toggleShakeToSummonAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.state = shakeToSummon ? .on : .off
        return item
    }

    @objc private func toggleShakeToSummonAction(_ sender: NSMenuItem) {
        shakeToSummon.toggle()
    }

    private func behaviorMenuItem() -> NSMenuItem {
        let behavior = NSMenuItem(title: "Behavior", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(dragOutMenuItem())
        submenu.addItem(autoShowWhileDraggingMenuItem())
        submenu.addItem(draggingEnabledMenuItem())
        submenu.addItem(shakeToSummonMenuItem())
        behavior.submenu = submenu
        return behavior
    }

    /// "Drag Out ▸ Move / Copy" — whether vending an item removes it or leaves a copy.
    private func dragOutMenuItem() -> NSMenuItem {
        let dragOut = NSMenuItem(title: "Drag Out", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let entries: [(String, Bool)] = [("Move", false), ("Copy", true)]
        for (title, copies) in entries {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectDragOutModeAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = copies
            item.state = (copies == vendCopies) ? .on : .off
            submenu.addItem(item)
        }
        dragOut.submenu = submenu
        return dragOut
    }

    @objc private func selectDragOutModeAction(_ sender: NSMenuItem) {
        guard let copies = sender.representedObject as? Bool else { return }
        vendCopies = copies
    }

    private func autoShowWhileDraggingMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Auto Show While Dragging",
            action: #selector(toggleRevealOnDragStartAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.state = revealOnDragStart ? .on : .off
        return item
    }

    @objc private func toggleRevealOnDragStartAction(_ sender: NSMenuItem) {
        revealOnDragStart.toggle()
    }

    @objc private func deleteMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        removeWithBounce(item, returnToOrigin: false)
        menuTargetItem = nil
    }

    @objc private func clearAllMenuAction(_ sender: NSMenuItem) {
        store.clearAll()
        menuTargetItem = nil
    }

    @objc private func quickLookMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        presentQuickLook(for: item)
    }

    // MARK: - Quick Look

    private func previewableURLs(for item: StoredItem) -> [URL] {
        item.backingFileURLs().filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func presentQuickLook(for item: StoredItem) {
        let urls = previewableURLs(for: item)
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
