import AppKit

/// RECEIVE → STORE: snapshot every representation of every pasteboard item into a
/// new `items/<uuid>/`, copy real files, and surface any promise receivers that
/// still need to be materialized.
@MainActor
struct PasteboardSnapshotter {
    let holding: HoldingDirectory

    func snapshot(
        _ pasteboard: NSPasteboard,
        into store: ItemStore
    ) throws -> (item: StoredItem, pendingPromises: [NSFilePromiseReceiver]) {
        fatalError("unimplemented")
    }
}
