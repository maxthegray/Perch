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
    /// URLs currently fed to `QLPreviewPanel`.
    private var quickLookURLs: [URL] = []

    /// When true, dragging an item out leaves the original on the shelf (copy);
    /// otherwise it's removed once it lands somewhere (move — the default).
    private static let vendCopiesKey = "Perch.VendCopies"
    private var vendCopies: Bool {
        get { UserDefaults.standard.bool(forKey: Self.vendCopiesKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.vendCopiesKey) }
    }

    /// Called with the SwiftUI content's measured natural height so the controller can
    /// size the window to fit.
    var onContentHeight: ((CGFloat) -> Void)?

    /// Called when the user picks "Show History…"; the controller opens the window.
    var onShowHistory: (() -> Void)?

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
        hostingView.rootView = ShelfContentView(
            store: store,
            themeStore: themeStore,
            interaction: interaction,
            thumbnails: thumbnails,
            ledger: ledger,
            onContentHeight: { [weak self] height in self?.onContentHeight?(height) }
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
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
        interaction.hoveredItemID = item(at: convert(event.locationInWindow, from: nil))?.id
    }

    override func mouseExited(with event: NSEvent) {
        interaction.hoveredItemID = nil
    }

    // MARK: - Delete button + row drag

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        resetDragState()

        if themeStore.theme.showsDeleteButton, themeStore.showsLabels,
           let index = rowIndex(at: point),
           deleteHitRect(forRow: index).contains(point) {
            pendingDeleteItem = store.items[index]
            return
        }

        dragItem = item(at: point)
        dragStartPoint = point
    }

    override func mouseDragged(with event: NSEvent) {
        // A press that started on a delete button must not turn into a drag.
        guard pendingDeleteItem == nil, !vendStarted, let item = dragItem else { return }
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
               index < store.items.count,
               store.items[index].id == item.id,
               deleteHitRect(forRow: index).contains(point) {
                // The ✕ puts the file back where it came from (right-click ▸ Delete
                // removes it for good).
                store.returnToOrigin(item)
            }
        } else if reorderActive {
            commitReorder()
        }
        resetDragState()
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
        let raw = Int((point.y + contentScrollOffsetY() - theme.contentPadding) / pitch)
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
        let dragSource = ItemDragSource(item: item)
        let ledger = ledger
        dragSource.recordVend = { entry in
            Task { @MainActor in ledger.record(entry) }
        }
        dragSource.onEnded = { [weak self] operation in
            guard let self else { return }
            self.activeDragSource = nil
            // Move semantics: once the item has landed somewhere, remove it from the
            // shelf. Deferred briefly so any in-flight file-promise write (which
            // copies from the holding dir) can finish before the dir is deleted.
            // In copy mode the original stays put.
            guard !operation.isEmpty, !self.vendCopies else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.store.remove(item)
            }
        }
        activeDragSource = dragSource
        _ = dragSource.beginDrag(from: self, event: event)
        NSLog("Perch row drag (vend) started for item \(item.id.uuidString)")
    }

    private func resetDragState() {
        dragItem = nil
        reorderActive = false
        vendStarted = false
        reorderBaseOrder = []
        interaction.draggingItemID = nil
        interaction.previewOrder = nil
    }

    private func item(at point: NSPoint) -> StoredItem? {
        rowIndex(at: point).map { store.items[$0] }
    }

    /// The index of the row under `point`, or nil. Mirrors ShelfContentView's layout:
    /// each row is `RowMetrics.height` tall, laid out with theme-driven spacing + outer
    /// padding. Accounts for scroll offset in the rare overflow (scrolling) case.
    private func rowIndex(at point: NSPoint) -> Int? {
        let theme = themeStore.theme
        let rowHeight = theme.rowHeight + theme.rowSpacing
        let topInset = theme.contentPadding
        let contentY = point.y + contentScrollOffsetY()
        let index = Int((contentY - topInset) / rowHeight)
        guard index >= 0, index < store.items.count else { return nil }
        return index
    }

    /// The clickable rect of a row's delete button, matching where ItemRowView draws it
    /// (trailing-aligned, vertically centered in the row), enlarged slightly for an
    /// easier target. Shifted by the scroll offset so it tracks the visible row.
    private func deleteHitRect(forRow index: Int) -> NSRect {
        let theme = themeStore.theme
        let rowTop = theme.contentPadding + CGFloat(index) * (theme.rowHeight + theme.rowSpacing)
        let centerY = rowTop + theme.rowHeight / 2 - contentScrollOffsetY()
        let centerX = bounds.width - theme.contentPadding
            - RowMetrics.deleteTrailingInset - RowMetrics.deleteDiameter / 2
        let hit = RowMetrics.deleteDiameter + 10
        return NSRect(x: centerX - hit / 2, y: centerY - hit / 2, width: hit, height: hit)
    }

    /// SwiftUI's `ScrollView` is backed by an `NSScrollView`; when the list overflows the
    /// screen and scrolls, read its content offset so the row math above stays correct.
    /// Returns 0 in the normal (non-overflowing) case.
    private func contentScrollOffsetY() -> CGFloat {
        var queue = hostingView.subviews
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let scrollView = view as? NSScrollView {
                return scrollView.contentView.bounds.origin.y
            }
            queue.append(contentsOf: view.subviews)
        }
        return 0
    }

    /// Grow/shrink the empty drop target while a drag is in flight.
    func setDropTarget(_ active: Bool) {
        interaction.isDropTarget = active
    }

    /// Clear any hover highlight / armed delete / in-flight reorder (called when the
    /// shelf hides so stale state doesn't carry into the next reveal).
    func resetInteraction() {
        interaction.hoveredItemID = nil
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

            if let entry = ledger.latestEntry(for: item.id) {
                let folder = folderName(entry.destination)
                let resend = NSMenuItem(
                    title: "Send to \(folder) Again",
                    action: #selector(resendMenuAction(_:)),
                    keyEquivalent: ""
                )
                resend.target = self
                resend.isEnabled = !item.backingFileURLs().isEmpty
                menu.addItem(resend)
            }

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
            title: "Show History…",
            action: #selector(showHistoryAction(_:)),
            keyEquivalent: ""
        )
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())
        menu.addItem(appearanceMenuItem())
        menu.addItem(edgesMenuItem())
        menu.addItem(dragOutMenuItem())

        let showNames = NSMenuItem(
            title: "Show Names",
            action: #selector(toggleShowLabelsAction(_:)),
            keyEquivalent: ""
        )
        showNames.target = self
        showNames.state = themeStore.showsLabels ? .on : .off
        menu.addItem(showNames)

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

    @objc private func showHistoryAction(_ sender: NSMenuItem) {
        onShowHistory?()
    }

    /// Re-send the right-clicked item to the folder it was last vended to, by copying
    /// its backing files there and recording the move.
    @objc private func resendMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem, let entry = ledger.latestEntry(for: item.id) else { return }
        menuTargetItem = nil
        let directory = URL(fileURLWithPath: entry.destination).deletingLastPathComponent()
        let copied = store.copyBackingFiles(of: item, toDirectory: directory)
        guard let first = copied.first else { return }
        ledger.record(ProvenanceEntry(
            id: item.id,
            title: item.metadata.title,
            origin: item.metadata.originPaths?.values.first,
            destination: first.path,
            vendedAt: Date(),
            wasCopy: true
        ))
    }

    /// The parent folder name of a file path, for compact menu labels.
    private func folderName(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    /// "Appearance ▸ Glass / Minimal" — toggles the active look live.
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
        appearance.submenu = submenu
        return appearance
    }

    @objc private func selectStyleAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ShelfStyle(rawValue: raw) else { return }
        themeStore.style = style
    }

    /// "Edges ▸ Left / Right / Top" — toggles which screen-edge docks are enabled.
    private func edgesMenuItem() -> NSMenuItem {
        let edges = NSMenuItem(title: "Edges", action: nil, keyEquivalent: "")
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

    @objc private func toggleShowLabelsAction(_ sender: NSMenuItem) {
        themeStore.showsLabels.toggle()
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

    @objc private func deleteMenuAction(_ sender: NSMenuItem) {
        guard let item = menuTargetItem else { return }
        store.remove(item)
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
