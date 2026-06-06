import AppKit

/// One persisted pasteboard representation, recorded in `meta.json`.
struct RepRecord: Codable, Equatable {
    let typeIdentifier: String
    let fileName: String
    let isPromisePlaceholder: Bool
}

/// On-disk metadata for a single stored item (`meta.json`).
struct ItemMetadata: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var title: String
    var representations: [RepRecord]
    var backingFileNames: [String]
    var primaryFileType: String?
}

/// A single item held by the shelf. Backed by `items/<uuid>/` on disk; reads
/// representation data and backing files lazily.
@MainActor
final class StoredItem: Identifiable {
    let metadata: ItemMetadata
    let directoryURL: URL

    init(metadata: ItemMetadata, directoryURL: URL) {
        fatalError("unimplemented")
    }

    nonisolated var id: UUID {
        fatalError("unimplemented")
    }

    /// Raw data for a representation, read from `reps/rep-N.dat`.
    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        fatalError("unimplemented")
    }

    /// Real files this item can vend (everything under `files/`).
    func backingFileURLs() -> [URL] {
        fatalError("unimplemented")
    }

    /// Display icon (Quick Look thumbnail or UTType icon).
    func iconImage() -> NSImage {
        fatalError("unimplemented")
    }
}
