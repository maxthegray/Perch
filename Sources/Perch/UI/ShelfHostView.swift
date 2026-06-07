import AppKit
import Quartz
import SwiftUI

/// AppKit host (`NSView`) for the SwiftUI shelf content, hosting `ShelfContentView`
/// via `NSHostingView`. This is the **primary** path (Decision M) for both:
///  - row drag-initiation (`mouseDragged(_:)` → owns/retains an `ItemDragSource`), and
///  - interactive controls (delete / clear-all / Quick Look — T12),
/// because a `.nonactivatingPanel` that never becomes key does not reliably deliver
/// SwiftUI gestures/controls. SwiftUI gestures are off the critical path.
final class ShelfHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private let store: ItemStore
    private let themeStore: ThemeStore
    private let interaction = RowInteractionState()
    private let hostingView: NSHostingView<ShelfContentView>
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?
    /// The row a context-menu action applies to (the row under the right-click).
    private var menuTargetItem: StoredItem?
    /// Set on mouse-down over a row's delete button; suppresses drag and, if the mouse
    /// is released still over the button, deletes the item.
    private var pendingDeleteItem: StoredItem?
    /// URLs currently fed to `QLPreviewPanel`.
    private var quickLookURLs: [URL] = []

    /// Called with the SwiftUI content's measured natural height so the controller can
    /// size the window to fit.
    var onContentHeight: ((CGFloat) -> Void)?

    init(store: ItemStore, themeStore: ThemeStore) {
        self.store = store
        self.themeStore = themeStore
        hostingView = NSHostingView(
            rootView: ShelfContentView(store: store, themeStore: themeStore, interaction: interaction)
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
        if themeStore.theme.showsDeleteButton,
           let index = rowIndex(at: point),
           deleteHitRect(forRow: index).contains(point) {
            pendingDeleteItem = store.items[index]
            return
        }
        pendingDeleteItem = nil
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let item = pendingDeleteItem else { return }
        pendingDeleteItem = nil

        let point = convert(event.locationInWindow, from: nil)
        if let index = rowIndex(at: point),
           index < store.items.count,
           store.items[index].id == item.id,
           deleteHitRect(forRow: index).contains(point) {
            store.remove(item)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        // A press that started on a delete button must not turn into a drag.
        guard pendingDeleteItem == nil else { return }

        guard let item = item(at: convert(event.locationInWindow, from: nil)) else {
            return
        }

        let dragSource = ItemDragSource(item: item)
        dragSource.onEnded = { [weak self] operation in
            guard let self else { return }
            self.activeDragSource = nil
            // Move semantics: once the item has landed somewhere, remove it from the
            // shelf. Deferred briefly so any in-flight file-promise write (which
            // copies from the holding dir) can finish before the dir is deleted.
            guard !operation.isEmpty else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.store.remove(item)
            }
        }
        activeDragSource = dragSource
        _ = dragSource.beginDrag(from: self, event: event)
        NSLog("Perch row drag started from ShelfHostView.mouseDragged for item \(item.id.uuidString)")
    }

    private func item(at point: NSPoint) -> StoredItem? {
        rowIndex(at: point).map { store.items[$0] }
    }

    /// The index of the row under `point`, or nil. Mirrors ShelfContentView's layout:
    /// each row is `RowMetrics.height` tall, laid out with theme-driven spacing + outer
    /// padding.
    private func rowIndex(at point: NSPoint) -> Int? {
        let theme = themeStore.theme
        let rowHeight = RowMetrics.height + theme.rowSpacing
        let topInset = theme.contentPadding
        let index = Int((point.y - topInset) / rowHeight)
        guard index >= 0, index < store.items.count else { return nil }
        return index
    }

    /// The clickable rect of a row's delete button, matching where ItemRowView draws it
    /// (trailing-aligned, vertically centered in the 44pt row), enlarged slightly for an
    /// easier target.
    private func deleteHitRect(forRow index: Int) -> NSRect {
        let theme = themeStore.theme
        let rowTop = theme.contentPadding + CGFloat(index) * (RowMetrics.height + theme.rowSpacing)
        let centerY = rowTop + RowMetrics.height / 2
        let centerX = bounds.width - theme.contentPadding
            - RowMetrics.deleteTrailingInset - RowMetrics.deleteDiameter / 2
        let hit = RowMetrics.deleteDiameter + 10
        return NSRect(x: centerX - hit / 2, y: centerY - hit / 2, width: hit, height: hit)
    }

    // MARK: - Context menu (AppKit; reliable while the panel is non-key)

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

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

        menu.addItem(.separator())
        menu.addItem(appearanceMenuItem())

        return menu
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
