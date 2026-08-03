import AppKit
import UniformTypeIdentifiers

/// One persisted pasteboard representation, recorded in `meta.json`.
struct RepRecord: Codable, Equatable {
    let typeIdentifier: String
    let fileName: String
    let isPromisePlaceholder: Bool
}

/// A durable pointer to a file that Perch deliberately left outside its holding
/// directory. The path is a fallback for bookmark failures and keeps old metadata
/// useful if bookmark resolution changes across macOS versions.
struct ReferencedFile: Codable, Equatable {
    let originalPath: String
    let bookmarkData: Data?

    init(url: URL) {
        originalPath = url.path
        bookmarkData = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolvedURL() -> URL {
        if let bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return URL(fileURLWithPath: originalPath)
    }
}

/// On-disk metadata for a single stored item (`meta.json`).
struct ItemMetadata: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var title: String
    var representations: [RepRecord]
    var backingFileNames: [String]
    var primaryFileType: String?
    /// Where each backing file was moved from (backing file name → original source
    /// path), so the shelf can put it back. Only set for file drops Perch took
    /// ownership of by moving; absent for clippings, promises, and copy fallbacks.
    var originPaths: [String: String]?
    /// Files intentionally left at their source (logical backing name → bookmark).
    /// Optional so metadata written by older Perch versions decodes unchanged.
    var referencedFiles: [String: ReferencedFile]? = nil
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

    /// Real files this item can vend. Most live under `files/`; reference-mode items
    /// resolve durable bookmarks to files that were deliberately left at their source.
    func backingFileURLs() -> [URL] {
        let filesDir = directoryURL.appendingPathComponent("files", isDirectory: true)
        return metadata.backingFileNames.map { fileName in
            if let reference = metadata.referencedFiles?[fileName] {
                return reference.resolvedURL()
            }
            return filesDir.appendingPathComponent(fileName, isDirectory: false)
        }
    }

    func isReferencedFile(named fileName: String) -> Bool {
        metadata.referencedFiles?[fileName] != nil
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
