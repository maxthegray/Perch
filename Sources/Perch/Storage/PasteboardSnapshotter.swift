import AppKit

/// One stored item produced by a drop, plus the work that still has to happen after
/// `performDragOperation` returns: file promises to materialize, and copy fallbacks
/// deferred off the main thread (a cross-volume or move-refused source would otherwise
/// copy synchronously inside the drop and beachball the app).
struct PasteboardSnapshotResult {
    let item: StoredItem
    let pendingPromises: [NSFilePromiseReceiver]
    let pendingCopies: [(source: URL, destination: URL)]
}

/// RECEIVE → STORE: snapshot every representation of every pasteboard item into a
/// new `items/<uuid>/`, take ownership of concrete files (or bookmark them when the
/// opt-in reference mode is enabled), and surface promises that still need materializing.
@MainActor
struct PasteboardSnapshotter {
    let holding: HoldingDirectory

    func snapshot(
        _ pasteboard: NSPasteboard,
        into store: ItemStore,
        insertionIndex: Int? = nil,
        referencesDroppedFiles: Bool? = nil
    ) throws -> [PasteboardSnapshotResult] {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        guard !pasteboardItems.isEmpty else { throw PasteboardSnapshotError.noItems }

        // Finder supplies file data lazily. Capture every representation before moving
        // any source file; moving the first selected file can otherwise invalidate data
        // that Finder has not supplied for the remaining selection yet.
        //
        // Items that yield nothing readable are skipped rather than failing the drop:
        // apps routinely advertise flavors whose data is unavailable at read time, and
        // one of those must not cost the user every other item in the drag.
        let capturedItems = pasteboardItems.compactMap(capture)
        guard !capturedItems.isEmpty else {
            throw PasteboardSnapshotError.noReadableRepresentations
        }
        let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []

        // Promise receivers cannot reliably be matched back to individual pasteboard
        // items, so retain the historical grouped behavior for promise-based drops.
        // Concrete Finder selections become one shelf row per selected file/item.
        let groups = receivers.isEmpty ? capturedItems.map { [$0] } : [capturedItems]
        var results: [PasteboardSnapshotResult] = []
        var createdDirectories: [URL] = []

        do {
            for group in groups {
                let directory = store.newItemDirectory()
                createdDirectories.append(directory.url)
                let expectedDirectoryURL = holding.itemDir(directory.id)
                guard directory.url == expectedDirectoryURL else {
                    throw PasteboardSnapshotError.holdingMismatch(
                        snapshotterURL: expectedDirectoryURL,
                        storeURL: directory.url
                    )
                }
                let (item, pendingCopies) = try writeSnapshot(
                    group,
                    id: directory.id,
                    directoryURL: directory.url,
                    referencesDroppedFiles: referencesDroppedFiles
                )
                results.append(PasteboardSnapshotResult(
                    item: item,
                    pendingPromises: receivers,
                    pendingCopies: pendingCopies
                ))
            }

            if receivers.isEmpty, let insertionIndex {
                for (offset, result) in results.enumerated() {
                    store.insert(result.item, at: insertionIndex + offset)
                }
            } else if receivers.isEmpty {
                // insert-at-front reverses its input, so insert backwards to preserve
                // Finder's selection order on the shelf.
                for result in results.reversed() { store.insert(result.item, at: nil) }
            }
            return results
        } catch {
            for directory in createdDirectories { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    func snapshotOwnedFile(
        _ fileURL: URL,
        into store: ItemStore,
        at insertionIndex: Int
    ) throws -> StoredItem {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("Perch.Transform.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        guard pasteboard.writeObjects([fileURL as NSURL]) else {
            throw PasteboardSnapshotError.noReadableRepresentations
        }
        defer { pasteboard.clearContents() }
        let results = try snapshot(
            pasteboard,
            into: store,
            insertionIndex: insertionIndex,
            referencesDroppedFiles: false
        )
        guard let item = results.first?.item else {
            throw PasteboardSnapshotError.noReadableRepresentations
        }
        return item
    }

    private struct CapturedItem {
        let representations: [(type: NSPasteboard.PasteboardType, data: Data?, isPromise: Bool)]
        let stringTitle: String?
    }

    /// Nil when nothing usable could be read off the item, so the caller can drop it
    /// without discarding the rest of the pasteboard.
    private func capture(_ pasteboardItem: NSPasteboardItem) -> CapturedItem? {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        var representations: [(NSPasteboard.PasteboardType, Data?, Bool)] = []

        for type in pasteboardItem.types where !type.isContextBoundSourceType {
            if promiseTypes.contains(type.rawValue) {
                representations.append((type, nil, true))
            } else if let data = pasteboardItem.data(forType: type) {
                representations.append((type, data, false))
            } else {
                NSLog("Perch skipped unreadable pasteboard flavor \(type.rawValue)")
            }
        }

        guard !representations.isEmpty else {
            NSLog("Perch skipped a pasteboard item with no readable representation")
            return nil
        }

        let title = pasteboardItem.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CapturedItem(
            representations: representations,
            stringTitle: title?.isEmpty == false ? title : nil
        )
    }

    private func writeSnapshot(
        _ capturedItems: [CapturedItem],
        id: UUID,
        directoryURL: URL,
        referencesDroppedFiles referenceOverride: Bool?
    ) throws -> (item: StoredItem, pendingCopies: [(source: URL, destination: URL)]) {
        let fileManager = FileManager.default
        let repsDir = directoryURL.appendingPathComponent("reps", isDirectory: true)
        let filesDir = directoryURL.appendingPathComponent("files", isDirectory: true)
        var representations: [RepRecord] = []
        var backingFileNames: [String] = []
        var originPaths: [String: String] = [:]
        var referencedFiles: [String: ReferencedFile] = [:]
        var pendingCopies: [(source: URL, destination: URL)] = []
        var stringTitle: String?
        var repIndex = 0
        var reservedBackingFileNames = Set<String>()
        let referencesDroppedFiles = referenceOverride ?? UserDefaults.standard.bool(
            forKey: PerchSettings.referenceDroppedFiles
        )

        for capturedItem in capturedItems {
            if stringTitle == nil { stringTitle = capturedItem.stringTitle }

            for captured in capturedItem.representations {
                let type = captured.type
                let fileName = "rep-\(repIndex).dat"
                repIndex += 1

                if captured.isPromise {
                    representations.append(
                        RepRecord(
                            typeIdentifier: type.rawValue,
                            fileName: fileName,
                            isPromisePlaceholder: true
                        )
                    )
                } else if let data = captured.data {
                    let repURL = repsDir.appendingPathComponent(fileName, isDirectory: false)
                    try data.write(to: repURL, options: .atomic)
                    representations.append(
                        RepRecord(
                            typeIdentifier: type.rawValue,
                            fileName: fileName,
                            isPromisePlaceholder: false
                        )
                    )
                } else {
                    throw PasteboardSnapshotError.missingData(type.rawValue)
                }

                if type == .fileURL {
                    let sourceURL = try fileURL(from: captured.data)
                    let destinationURL = uniqueDestinationURL(
                        for: sourceURL.lastPathComponent,
                        in: filesDir,
                        fileManager: fileManager,
                        reservedFileNames: reservedBackingFileNames
                    )
                    let backingFileName = destinationURL.lastPathComponent
                    reservedBackingFileNames.insert(backingFileName)

                    if referencesDroppedFiles {
                        referencedFiles[backingFileName] = ReferencedFile(url: sourceURL)
                    } else {
                        // Take ownership: MOVE the original into the shelf so it leaves
                        // its source. Fall back to copy if the move isn't permitted
                        // (e.g. read-only source or cross-volume restriction) so the drop
                        // still succeeds rather than failing.
                        do {
                            try fileManager.moveItem(at: sourceURL, to: destinationURL)
                            // Remember where it came from so the shelf can put it back.
                            originPaths[backingFileName] = sourceURL.path
                        } catch {
                            NSLog("Perch could not move \(sourceURL.path) into shelf (\(error)); copying instead")
                            // Deferred off the main thread: a cross-volume copy of a
                            // large file here would beachball the app mid-drop.
                            pendingCopies.append((source: sourceURL, destination: destinationURL))
                        }
                    }
                    backingFileNames.append(backingFileName)
                }
            }
        }

        let metadata = ItemMetadata(
            id: id,
            createdAt: Date(),
            title: title(backingFileNames: backingFileNames, stringTitle: stringTitle, id: id),
            representations: representations,
            backingFileNames: backingFileNames,
            primaryFileType: representations.first?.typeIdentifier,
            originPaths: originPaths.isEmpty ? nil : originPaths,
            referencedFiles: referencedFiles.isEmpty ? nil : referencedFiles
        )
        let metaURL = directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return (StoredItem(metadata: metadata, directoryURL: directoryURL), pendingCopies)
    }

    private func fileURL(from data: Data?) throws -> URL {
        if let data,
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return url
        }

        throw PasteboardSnapshotError.invalidFileURL
    }

    private func uniqueDestinationURL(
        for fileName: String,
        in directory: URL,
        fileManager: FileManager,
        reservedFileNames: Set<String> = []
    ) -> URL {
        let baseName = fileName.isEmpty ? "file" : fileName
        let initialURL = directory.appendingPathComponent(baseName, isDirectory: false)
        guard reservedFileNames.contains(baseName)
                || fileManager.fileExists(atPath: initialURL.path) else {
            return initialURL
        }

        let originalName = (baseName as NSString).deletingPathExtension
        let pathExtension = (baseName as NSString).pathExtension
        var suffix = 2

        while true {
            let candidateName: String
            if pathExtension.isEmpty {
                candidateName = "\(originalName)-\(suffix)"
            } else {
                candidateName = "\(originalName)-\(suffix).\(pathExtension)"
            }

            let candidateURL = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !reservedFileNames.contains(candidateName),
               !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            suffix += 1
        }
    }

    private func title(backingFileNames: [String], stringTitle: String?, id: UUID) -> String {
        if let firstFileName = backingFileNames.first, !firstFileName.isEmpty {
            return firstFileName
        }

        if let stringTitle, !stringTitle.isEmpty {
            return String(stringTitle.prefix(80))
        }

        return "Item \(id.uuidString.prefix(8))"
    }
}

private enum PasteboardSnapshotError: Error {
    case noItems
    case noReadableRepresentations
    case holdingMismatch(snapshotterURL: URL, storeURL: URL)
    case invalidFileURL
    case missingData(String)
}
