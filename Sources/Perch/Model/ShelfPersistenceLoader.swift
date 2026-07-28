import Foundation

/// Loads the shelf's independent persistence stores without letting damage in one
/// suppress the other. In particular, a corrupt `index.json` must not leave the
/// provenance ledger empty in memory, where the next vend would overwrite its history.
@MainActor
enum ShelfPersistenceLoader {
    static func load(store: ItemStore, ledger: ProvenanceLedger) throws {
        defer { ledger.load() }
        try store.load()
    }
}
