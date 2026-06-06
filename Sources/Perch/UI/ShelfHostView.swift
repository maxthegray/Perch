import AppKit
import SwiftUI

/// AppKit host (`NSView`) for the SwiftUI shelf content, hosting `ShelfContentView`
/// via `NSHostingView`. This is the **primary** path (Decision M) for both:
///  - row drag-initiation (`mouseDragged(_:)` → owns/retains an `ItemDragSource`), and
///  - interactive controls (delete / clear-all / Quick Look — T12),
/// because a `.nonactivatingPanel` that never becomes key does not reliably deliver
/// SwiftUI gestures/controls. SwiftUI gestures are off the critical path.
final class ShelfHostView: NSView {
    private let store: ItemStore
    private let hostingView: NSHostingView<ShelfContentView>
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?

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
}
