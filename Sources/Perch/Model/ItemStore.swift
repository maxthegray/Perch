import Combine
import Foundation

enum ItemStoreRenameError: Error, Equatable {
    case itemNotFound
    case requiresSingleBackingFile
    case invalidFilename
    case extensionChanged
    case backingFileMissing
}

/// In-memory ordered list of stored items plus the persistence facade over the
/// holding directory.
@MainActor
final class ItemStore: ObservableObject {
    @Published private(set) var items: [StoredItem] = []

    /// The most recently stashed item, briefly published so its row can flash an accent
    /// ring to confirm the drop landed. Cleared automatically after a short delay.
    @Published private(set) var justAddedItemID: UUID?

    private let holding: HoldingDirectory
    private var justAddedClearTask: Task<Void, Never>?
    private var retireDeletionTasks: [UUID: Task<Void, Never>] = [:]

    /// Item directories that exist on disk but could not be turned into rows this
    /// launch — an unreadable `meta.json`, or an `index.json` we could not parse at
    /// all. They are written back into `index.json` on every persist and are never
    /// swept, so a transient read failure can never escalate into permanent deletion
    /// of the user's files. A later launch that can read them adopts them as rows.
    private var protectedItemIDs: Set<UUID> = []

    /// True when `load()` could not fully reconcile the store against the index. While
    /// degraded, every destructive reconciliation path (the orphan sweep) is disabled.
    private(set) var isDegraded = false

    /// Fired with the URLs a return-to-origin actually restored, so the controller can
    /// silence them as recent-arrival offers (the shelf must never offer back a file
    /// the user just put down).
    var onFilesRestored: (([URL]) -> Void)?

    init(holding: HoldingDirectory) {
        self.holding = holding
    }

    /// Load items from `index.json` + each `meta.json`.
    ///
    /// Failures are contained rather than fatal: one damaged item must never cost the
    /// user the rest of the shelf. Anything that cannot be read becomes a *protected*
    /// ID (kept in the index, never swept) and puts the store into degraded mode.
    func load() throws {
        try ensureBaseDirectories()
        items = []
        protectedItemIDs = []
        isDegraded = false

        guard FileManager.default.fileExists(atPath: holding.indexFile.path) else {
            // A missing index is not evidence that the item directories are garbage —
            // it is much more likely that the index write was lost. Protect whatever
            // is on disk so a later launch can still recover it.
            protectItemDirectoriesOnDisk(reason: "index.json is missing")
            return
        }

        let orderedIDs: [UUID]
        do {
            orderedIDs = try JSONDecoder().decode(
                [UUID].self,
                from: Data(contentsOf: holding.indexFile)
            )
        } catch {
            protectItemDirectoriesOnDisk(reason: "index.json is unreadable (\(error))")
            throw error
        }

        var loadedItems: [StoredItem] = []
        var unresolvedIDs: Set<UUID> = []
        for id in orderedIDs {
            let itemDir = holding.itemDir(id)
            let metaURL = itemDir.appendingPathComponent("meta.json", isDirectory: false)
            do {
                let metadata = try JSONDecoder().decode(
                    ItemMetadata.self,
                    from: Data(contentsOf: metaURL)
                )
                loadedItems.append(StoredItem(metadata: metadata, directoryURL: itemDir))
            } catch {
                // Only treat this as recoverable damage while the directory is still
                // there. An index entry whose directory is simply gone is stale
                // bookkeeping, not a file we could lose.
                if FileManager.default.fileExists(atPath: itemDir.path) {
                    unresolvedIDs.insert(id)
                    NSLog("Perch could not read \(metaURL.path): \(error); preserving its files")
                }
            }
        }

        items = loadedItems
        protectedItemIDs = unresolvedIDs
        guard unresolvedIDs.isEmpty else {
            isDegraded = true
            NSLog(
                "Perch loaded in degraded mode: \(unresolvedIDs.count) unreadable item(s) preserved, orphan sweep skipped"
            )
            return
        }
        sweepOrphanedItemDirs(keeping: Set(orderedIDs))
    }

    /// Enter degraded mode and adopt every `items/<uuid>/` directory as protected. Used
    /// when the index itself is unusable, so the directories survive to be recovered.
    private func protectItemDirectoriesOnDisk(reason: String) {
        let onDiskIDs = itemDirectoryIDsOnDisk()
        guard !onDiskIDs.isEmpty else { return }
        isDegraded = true
        protectedItemIDs = onDiskIDs
        NSLog(
            "Perch loaded in degraded mode: \(reason); preserving \(onDiskIDs.count) item director(ies)"
        )
    }

    private func itemDirectoryIDsOnDisk() -> Set<UUID> {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: holding.itemsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        return Set(entries.compactMap { UUID(uuidString: $0.lastPathComponent) })
    }

    /// Insert an item at `index` (nil = front) and update `index.json`.
    func insert(_ item: StoredItem, at index: Int?) {
        let insertionIndex = min(max(index ?? 0, 0), items.count)
        items.insert(item, at: insertionIndex)
        persistIndexOrLogFailure()
        flashJustAdded(item.id)
    }

    /// Mark `id` as freshly stashed so its row pulses an accent ring, then clear it after
    /// a beat. A newer insert supersedes an in-flight flash.
    private func flashJustAdded(_ id: UUID) {
        justAddedItemID = id
        justAddedClearTask?.cancel()
        justAddedClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled else { return }
            self?.justAddedItemID = nil
        }
    }

    /// Replace the display order with `ordered` (a permutation of the current items) and
    /// persist it. Used by drag-to-reorder.
    func setOrder(_ ordered: [StoredItem]) {
        guard ordered.count == items.count else { return }
        items = ordered
        persistIndexOrLogFailure()
    }

    /// Rename a one-file shelf item in place and atomically persist its updated
    /// metadata. Name collisions are uniquified instead of overwriting another file.
    @discardableResult
    func renameSingleBackingFile(
        of item: StoredItem,
        to proposedFilename: String
    ) throws -> StoredItem {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else {
            throw ItemStoreRenameError.itemNotFound
        }
        guard item.metadata.backingFileNames.count == 1,
              let oldFilename = item.metadata.backingFileNames.first
        else {
            throw ItemStoreRenameError.requiresSingleBackingFile
        }

        let trimmedFilename = proposedFilename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedFilename.isEmpty,
              trimmedFilename != ".",
              trimmedFilename != "..",
              (trimmedFilename as NSString).lastPathComponent == trimmedFilename
        else {
            throw ItemStoreRenameError.invalidFilename
        }

        let oldExtension = (oldFilename as NSString).pathExtension
        let newExtension = (trimmedFilename as NSString).pathExtension
        guard !oldExtension.isEmpty,
              oldExtension.caseInsensitiveCompare(newExtension) == .orderedSame
        else {
            throw ItemStoreRenameError.extensionChanged
        }

        let filesDirectory = item.directoryURL.appendingPathComponent(
            "files",
            isDirectory: true
        )
        let sourceURL = filesDirectory.appendingPathComponent(
            oldFilename,
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ItemStoreRenameError.backingFileMissing
        }

        let proposedURL = filesDirectory.appendingPathComponent(
            trimmedFilename,
            isDirectory: false
        )
        // A case-only rename on a case-insensitive volume names the *same* file, so
        // the collision check must not treat the file as blocking itself (which would
        // silently hand back `Photo-2.png` for `photo.png` → `Photo.png`).
        let destinationURL = Self.refersToSameFile(proposedURL, sourceURL)
            ? proposedURL
            : nonClobberingURL(for: proposedURL, fileManager: .default)
        let finalFilename = destinationURL.lastPathComponent

        var metadata = item.metadata
        metadata.backingFileNames = [finalFilename]
        metadata.title = finalFilename
        if var originPaths = metadata.originPaths,
           let originPath = originPaths.removeValue(forKey: oldFilename) {
            originPaths[finalFilename] = originPath
            metadata.originPaths = originPaths
        }

        let metadataURL = item.directoryURL.appendingPathComponent(
            "meta.json",
            isDirectory: false
        )
        var movedFile = false
        do {
            try Self.moveBackingFile(from: sourceURL, to: destinationURL)
            movedFile = true
            try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
        } catch {
            if movedFile {
                try? Self.moveBackingFile(from: destinationURL, to: sourceURL)
            }
            throw error
        }

        let renamedItem = StoredItem(
            metadata: metadata,
            directoryURL: item.directoryURL
        )
        var updatedItems = items
        updatedItems[itemIndex] = renamedItem
        items = updatedItems
        return renamedItem
    }

    /// Put an item's backing files back where they were taken from, then remove the
    /// item from the shelf. Files with no recorded origin (clippings, promise-backed
    /// files, copy fallbacks) have nowhere to return to, so the item is just removed.
    /// Never overwrites: a name clash at the destination is uniquified. Returns the
    /// URLs successfully restored.
    @discardableResult
    func returnToOrigin(_ item: StoredItem) -> [URL] {
        return returnToOrigin([item])
    }

    /// Return a selection as one store mutation so observers never see partially
    /// removed batches and resize the shelf once per row.
    @discardableResult
    func returnToOrigin(_ items: [StoredItem]) -> [URL] {
        let restored = items.flatMap(restoreBackingFiles)
        remove(items)
        if !restored.isEmpty {
            onFilesRestored?(restored)
        }
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

    /// Whether two URLs name the same file on disk — true for a case-only difference
    /// on a case-insensitive volume, false when either side does not exist.
    private static func refersToSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsID = try? lhs.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier,
        let rhsID = try? rhs.resourceValues(
            forKeys: [.fileResourceIdentifierKey]
        ).fileResourceIdentifier
        else { return false }
        return lhsID.isEqual(rhsID)
    }

    /// Rename a file inside an item's `files/` directory. `moveItem` refuses a
    /// case-only rename on a case-insensitive volume (it sees the destination as an
    /// existing file), so that case goes through a temporary name.
    private static func moveBackingFile(from source: URL, to destination: URL) throws {
        guard source.path != destination.path else { return }
        guard refersToSameFile(source, destination) else {
            try FileManager.default.moveItem(at: source, to: destination)
            return
        }

        let temporaryURL = source
            .deletingLastPathComponent()
            .appendingPathComponent("perch-rename-\(UUID().uuidString)", isDirectory: false)
        try FileManager.default.moveItem(at: source, to: temporaryURL)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            try? FileManager.default.moveItem(at: temporaryURL, to: source)
            throw error
        }
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

    /// Remove a vended item from the shelf but leave its `items/<uuid>/` directory on
    /// disk: the drag pasteboard's concrete file URL (and any not-yet-called-in file
    /// promise) points into it, and destinations like Messages read the dropped file
    /// well after the drop lands. The orphaned directory is deleted after a generous
    /// grace period; `load()` sweeps any leftovers on the next launch.
    func retire(_ item: StoredItem) {
        items.removeAll { $0.id == item.id }
        persistIndexOrLogFailure()

        let directoryURL = item.directoryURL
        let id = item.id
        retireDeletionTasks[id]?.cancel()
        retireDeletionTasks[id] = Task.detached(priority: .background) { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            guard let self else {
                try? FileManager.default.removeItem(at: directoryURL)
                return
            }
            await self.completeRetireDeletion(of: id, at: directoryURL)
        }
    }

    /// Delete a retired item's directory once the grace period elapses. Runs on the
    /// main actor so it serializes against `unretire`: an unretire whose `cancel()`
    /// lands after the sleep already finished would otherwise race the deletion and
    /// destroy the backing directory of a row it just restored to the shelf.
    private func completeRetireDeletion(of id: UUID, at directoryURL: URL) {
        guard !Task.isCancelled, !items.contains(where: { $0.id == id }) else { return }
        retireDeletionTasks[id] = nil
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// Put a retired item back on the shelf: the destination accepted the drop but then
    /// failed to take delivery (e.g. its promise write was denied), so the vend never
    /// actually happened. Cancels the pending grace-period deletion.
    func unretire(_ item: StoredItem) {
        retireDeletionTasks[item.id]?.cancel()
        retireDeletionTasks[item.id] = nil
        guard !items.contains(where: { $0.id == item.id }),
              FileManager.default.fileExists(atPath: item.directoryURL.path) else { return }
        insert(item, at: nil)
    }

    /// Delete `items/<uuid>/` directories that are not in the index — left behind by
    /// `retire(_:)` when the app quit before the grace period elapsed.
    private func sweepOrphanedItemDirs(keeping ids: Set<UUID>) {
        // Never reconcile destructively against an index we could not fully resolve.
        guard !isDegraded else { return }
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: holding.itemsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), !ids.contains(id) else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    /// Remove an item and delete its `items/<uuid>/` directory.
    func remove(_ item: StoredItem) {
        remove([item])
    }

    /// Permanently remove several items in one published update.
    func remove(_ removedItems: [StoredItem]) {
        let removedIDs = Set(removedItems.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }

        for item in removedItems {
            do {
                try FileManager.default.removeItem(at: item.directoryURL)
            } catch CocoaError.fileNoSuchFile {
                // Already absent; the in-memory order and index still need updating.
            } catch {
                NSLog("Perch failed to remove item directory \(item.directoryURL.path): \(error)")
            }
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
        let data = try JSONEncoder().encode(persistableOrderedIDs())
        try data.write(to: holding.indexFile, options: .atomic)
    }

    /// The rows in display order, followed by any protected IDs whose directory is
    /// still on disk. Rewriting the index without the protected IDs is what turns a
    /// one-launch read failure into permanent deletion on the launch after that, so
    /// they ride along in every write until they are either recovered or deleted.
    private func persistableOrderedIDs() -> [UUID] {
        let liveIDs = Set(items.map(\.id))
        let preserved = protectedItemIDs
            .subtracting(liveIDs)
            .filter { FileManager.default.fileExists(atPath: holding.itemDir($0).path) }
        return items.map(\.id) + preserved.sorted { $0.uuidString < $1.uuidString }
    }

    private func persistIndexOrLogFailure() {
        do {
            try persistIndex()
        } catch {
            NSLog("Perch failed to persist index.json: \(error)")
        }
    }
}
