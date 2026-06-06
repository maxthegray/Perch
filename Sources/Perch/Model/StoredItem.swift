import AppKit
import UniformTypeIdentifiers

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
        self.metadata = metadata
        self.directoryURL = directoryURL
    }

    nonisolated var id: UUID {
        metadata.id
    }

    /// Raw data for a representation, read from `reps/rep-N.dat`.
    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        guard let record = metadata.representations.first(where: {
            $0.typeIdentifier == type.rawValue && !$0.isPromisePlaceholder
        }) else {
            return nil
        }

        let url = directoryURL
            .appendingPathComponent("reps", isDirectory: true)
            .appendingPathComponent(record.fileName, isDirectory: false)
        return try? Data(contentsOf: url)
    }

    /// Real files this item can vend (everything under `files/`).
    func backingFileURLs() -> [URL] {
        let filesDir = directoryURL.appendingPathComponent("files", isDirectory: true)
        return metadata.backingFileNames.map {
            filesDir.appendingPathComponent($0, isDirectory: false)
        }
    }

    /// Display icon (Quick Look thumbnail or UTType icon).
    func iconImage() -> NSImage {
        if let fileURL = backingFileURLs().first {
            return NSWorkspace.shared.icon(forFile: fileURL.path)
        }

        if let primaryFileType = metadata.primaryFileType,
           let contentType = UTType(primaryFileType) {
            return NSWorkspace.shared.icon(for: contentType)
        }

        if let firstType = metadata.representations.first?.typeIdentifier,
           let contentType = UTType(firstType) {
            return NSWorkspace.shared.icon(for: contentType)
        }

        return NSWorkspace.shared.icon(for: .data)
    }
}
