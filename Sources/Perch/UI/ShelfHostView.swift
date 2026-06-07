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
    private let hostingView: NSHostingView<ShelfContentView>
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?
    /// The row a context-menu action applies to (the row under the right-click).
    private var menuTargetItem: StoredItem?
    /// URLs currently fed to `QLPreviewPanel`.
    private var quickLookURLs: [URL] = []

    init(store: ItemStore) {
        self.store = store
        hostingView = NSHostingView(rootView: ShelfContentView(store: store))
        super.init(frame: .zero)
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item = item(at: convert(event.locationInWindow, from: nil)) else {
            return
        }

        let dragSource = ItemDragSource(item: item)
        activeDragSource = dragSource
        _ = dragSource.beginDrag(from: self, event: event)
        NSLog("Perch row drag started from ShelfHostView.mouseDragged for item \(item.id.uuidString)")
    }

    private func item(at point: NSPoint) -> StoredItem? {
        let rowHeight: CGFloat = 48
        let topInset: CGFloat = 8
        let rowIndex = Int((point.y - topInset) / rowHeight)

        guard rowIndex >= 0, rowIndex < store.items.count else {
            return nil
        }

        return store.items[rowIndex]
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

        return menu
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
