import AppKit

/// RE-VEND: a single object that is simultaneously the file-promise provider, the
/// lazy generic-data provider, and (via the delegate) the on-demand file writer.
/// Subclasses `NSFilePromiseProvider` and *adds* the item's stored generic types
/// on top of the file delivery (Decision F).
///
/// File delivery is **promise-preferred**: the promise is the primary file path
/// (it writes a fresh copy and never exposes the holding-dir master); the concrete
/// holding-dir file URL is offered only as an instant-local convenience. The drag is
/// `.copy`-only (enforced by `ItemDragSource`, Decision K).
final class StoredItemDragWriter: NSFilePromiseProvider {
    convenience init(item: StoredItem) {
        fatalError("unimplemented")
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        fatalError("unimplemented")
    }

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        fatalError("unimplemented")
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        fatalError("unimplemented")
    }
}

/// Supplies the promised filename and writes the file from the holding dir, off
/// the main actor on its own operation queue.
final class StoredItemDragWriterDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let item: StoredItem

    init(item: StoredItem) {
        self.item = item
        super.init()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        fatalError("unimplemented")
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        fatalError("unimplemented")
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        fatalError("unimplemented")
    }
}
