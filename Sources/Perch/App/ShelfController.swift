import AppKit
import Darwin

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    private let panel: ShelfPanel
    private let holding: HoldingDirectory
    private let store: ItemStore
    private let snapshotter: PasteboardSnapshotter
    private let promiseMaterializer: FilePromiseMaterializer
    private let dropView: ShelfDropView
    private let hostView: ShelfHostView

    init() throws {
        holding = try HoldingDirectory.standard()
        store = ItemStore(holding: holding)
        snapshotter = PasteboardSnapshotter(holding: holding)
        promiseMaterializer = FilePromiseMaterializer()
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

            if !result.pendingPromises.isEmpty {
                materializePendingPromises(for: result.item, receivers: result.pendingPromises, initialCount: beforeCount)
            }

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

    private func materializePendingPromises(
        for item: StoredItem,
        receivers: [NSFilePromiseReceiver],
        initialCount: Int
    ) {
        let filesDir = item.directoryURL.appendingPathComponent("files", isDirectory: true)

        promiseMaterializer.materialize(receivers, into: filesDir) { [weak self] materializedURLs in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let beforeInsertMainThread = pthread_main_np() == 1
                do {
                    let finalItem = try self.itemByAppendingMaterializedFiles(
                        materializedURLs,
                        to: item
                    )
                    self.store.insert(finalItem, at: nil)

                    let repTypes = finalItem.metadata.representations.map(\.typeIdentifier).joined(separator: ",")
                    let backingFiles = finalItem.backingFileURLs().map(\.lastPathComponent).joined(separator: ",")
                    NSLog(
                        "Perch promise materialization stored item \(finalItem.id.uuidString); count \(initialCount)->\(self.store.items.count); reps [\(repTypes)]; files [\(backingFiles)]; mainThread \(beforeInsertMainThread)"
                    )
                } catch {
                    NSLog("Perch promise materialization failed for item \(item.id.uuidString): \(error)")
                    try? FileManager.default.removeItem(at: item.directoryURL)
                }
            }
        }
    }

    private func itemByAppendingMaterializedFiles(
        _ materializedURLs: [URL],
        to item: StoredItem
    ) throws -> StoredItem {
        var metadata = item.metadata
        let existingFileNames = Set(metadata.backingFileNames)
        let newFileNames = materializedURLs
            .map(\.lastPathComponent)
            .filter { !$0.isEmpty && !existingFileNames.contains($0) }

        metadata.backingFileNames.append(contentsOf: newFileNames)
        if metadata.backingFileNames.count == newFileNames.count,
           let firstFileName = newFileNames.first {
            metadata.title = firstFileName
        }

        let metaURL = item.directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return StoredItem(metadata: metadata, directoryURL: item.directoryURL)
    }
}
