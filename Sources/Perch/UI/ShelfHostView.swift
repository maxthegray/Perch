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
    /// Retains the active drag source for the lifetime of an in-flight drag.
    private var activeDragSource: ItemDragSource?

    init(store: ItemStore) {
        fatalError("unimplemented")
    }

    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override func mouseDragged(with event: NSEvent) {
        // T5: identify the hit row, create + retain an `ItemDragSource`, and call
        // `beginDrag(from:event:)`.
        fatalError("unimplemented")
    }
}
