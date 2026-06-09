import Combine
import Foundation

/// In-memory ordered list of stored items plus the persistence facade over the
/// holding directory.
@MainActor
final class ItemStore: ObservableObject {
    @Published private(set) var items: [StoredItem] = []

    private let holding: HoldingDirectory

    init(holding: HoldingDirectory) {
        self.holding = holding
    }

    /// Load items from `index.json` + each `meta.json`.
    func load() throws {
        try ensureBaseDirectories()

        guard FileManager.default.fileExists(atPath: holding.indexFile.path) else {
            items = []
            return
        }

        let orderedIDs = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: holding.indexFile))
        items = try orderedIDs.map { id in
            let itemDir = holding.itemDir(id)
            let metaURL = itemDir.appendingPathComponent("meta.json", isDirectory: false)
            let metadata = try JSONDecoder().decode(ItemMetadata.self, from: Data(contentsOf: metaURL))
            return StoredItem(metadata: metadata, directoryURL: itemDir)
        }
    }

    /// Insert an item at `index` (nil = front) and update `index.json`.
    func insert(_ item: StoredItem, at index: Int?) {
        let insertionIndex = min(max(index ?? 0, 0), items.count)
        items.insert(item, at: insertionIndex)
        persistIndexOrLogFailure()
    }

    /// Replace the display order with `ordered` (a permutation of the current items) and
    /// persist it. Used by drag-to-reorder.
    func setOrder(_ ordered: [StoredItem]) {
        guard ordered.count == items.count else { return }
        items = ordered
        persistIndexOrLogFailure()
    }

    /// Put an item's backing files back where they were taken from, then remove the
    /// item from the shelf. Files with no recorded origin (clippings, promise-backed
    /// files, copy fallbacks) have nowhere to return to, so the item is just removed.
    /// Never overwrites: a name clash at the destination is uniquified. Returns the
    /// URLs successfully restored.
    @discardableResult
    func returnToOrigin(_ item: StoredItem) -> [URL] {
        let restored = restoreBackingFiles(of: item)
        remove(item)
        return restored
    }

    private func restoreBackingFiles(of item: StoredItem) -> [URL] {
        guard let origins = item.metadata.originPaths, !origins.isEmpty else { return [] }
        let fileManager = FileManager.default
        let filesDir = item.directoryURL.appendingPathComponent("files", isDirectory: true)
        var restored: [URL] = []

        for (fileName, originPath) in origins {
            let source = filesDir.appendingPathComponent(fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            let originURL = URL(fileURLWithPath: originPath)
            do {
                try fileManager.createDirectory(
                    at: originURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let destination = nonClobberingURL(for: originURL, fileManager: fileManager)
                try fileManager.moveItem(at: source, to: destination)
                restored.append(destination)
            } catch {
                NSLog("Perch could not return \(fileName) to \(originPath): \(error)")
            }
        }
        return restored
    }

    /// `url` if it's free, otherwise the same name with a `-2`, `-3`, … suffix.
    private func nonClobberingURL(for url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var suffix = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
            let candidate = directory.appendingPathComponent(name, isDirectory: false)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    /// Remove an item and delete its `items/<uuid>/` directory.
    func remove(_ item: StoredItem) {
        items.removeAll { $0.id == item.id }

        do {
            try FileManager.default.removeItem(at: item.directoryURL)
        } catch CocoaError.fileNoSuchFile {
            // Already absent; the in-memory order and index still need to be updated.
        } catch {
            NSLog("Perch failed to remove item directory \(item.directoryURL.path): \(error)")
        }

        persistIndexOrLogFailure()
    }

    /// Remove every item and delete all `items/<uuid>/` directories.
    func clearAll() {
        for item in items {
            do {
                try FileManager.default.removeItem(at: item.directoryURL)
            } catch CocoaError.fileNoSuchFile {
                // Already absent; continue.
            } catch {
                NSLog("Perch failed to remove item directory \(item.directoryURL.path): \(error)")
            }
        }

        items.removeAll()
        persistIndexOrLogFailure()
    }

    /// Create a fresh `items/<uuid>/{reps,files}` directory and return its id + url.
    func newItemDirectory() -> (id: UUID, url: URL) {
        let id = UUID()
        let itemDir = holding.itemDir(id)

        do {
            try FileManager.default.createDirectory(
                at: itemDir.appendingPathComponent("reps", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: itemDir.appendingPathComponent("files", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            preconditionFailure("Perch failed to create item directory \(itemDir.path): \(error)")
        }

        return (id, itemDir)
    }

    private func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: holding.itemsDir, withIntermediateDirectories: true)
    }

    private func persistIndex() throws {
        try ensureBaseDirectories()
        let orderedIDs = items.map(\.id)
        let data = try JSONEncoder().encode(orderedIDs)
        try data.write(to: holding.indexFile, options: .atomic)
    }

    private func persistIndexOrLogFailure() {
        do {
            try persistIndex()
        } catch {
            NSLog("Perch failed to persist index.json: \(error)")
        }
    }
}
