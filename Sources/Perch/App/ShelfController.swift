import AppKit

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    private let panel: ShelfPanel
    private let holding: HoldingDirectory
    private let store: ItemStore
    private let snapshotter: PasteboardSnapshotter
    private let dropView: ShelfDropView
    private let hostView: ShelfHostView

    init() throws {
        holding = try HoldingDirectory.standard()
        store = ItemStore(holding: holding)
        snapshotter = PasteboardSnapshotter(holding: holding)
        panel = ShelfPanel(contentRect: Self.initialPanelFrame())
        dropView = ShelfDropView(frame: panel.contentView?.bounds ?? .zero)
        hostView = ShelfHostView(store: store)
        dropView.autoresizingMask = [.width, .height]
        dropView.dropHandler = self
        hostView.frame = dropView.bounds
        hostView.autoresizingMask = [.width, .height]
        dropView.addSubview(hostView)
        panel.contentView = dropView
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        do {
            try store.load()
            NSLog("Perch loaded \(store.items.count) stored item(s)")
        } catch {
            NSLog("Perch failed to load stored items: \(error)")
        }

        panel.orderFrontRegardless()
    }

    // MARK: ShelfDropHandling

    func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        let beforeCount = store.items.count

        do {
            let result = try snapshotter.snapshot(pasteboard, into: store)
            let afterCount = store.items.count
            let repTypes = result.item.metadata.representations.map(\.typeIdentifier).joined(separator: ",")
            let backingFiles = result.item.backingFileURLs().map(\.lastPathComponent).joined(separator: ",")

            NSLog(
                "Perch drop stored item \(result.item.id.uuidString); count \(beforeCount)->\(afterCount); reps [\(repTypes)]; files [\(backingFiles)]; pendingPromises \(result.pendingPromises.count)"
            )
            return true
        } catch {
            NSLog("Perch drop failed: \(error)")
            return false
        }
    }

    // MARK: EdgeStripDelegate

    func edgeStripDidReceiveDrag(_ strip: EdgeStripWindow) {
        fatalError("unimplemented")
    }

    private static func initialPanelFrame() -> NSRect {
        let fallbackFrame = NSRect(x: 0, y: 0, width: 320, height: 640)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? fallbackFrame
        let width = min(CGFloat(320), visibleFrame.width)

        return NSRect(
            x: visibleFrame.maxX - width,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
    }
}
