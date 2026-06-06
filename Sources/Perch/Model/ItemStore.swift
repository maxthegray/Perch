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
