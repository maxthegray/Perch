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
    ) throws -> [(item: StoredItem, pendingPromises: [NSFilePromiseReceiver])] {
        let pasteboardItems = pasteboard.pasteboardItems ?? []
        guard !pasteboardItems.isEmpty else { throw PasteboardSnapshotError.noItems }

        // Finder supplies file data lazily. Capture every representation before moving
        // any source file; moving the first selected file can otherwise invalidate data
        // that Finder has not supplied for the remaining selection yet.
        let capturedItems = try pasteboardItems.map(capture)
        let receivers = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []

        // Promise receivers cannot reliably be matched back to individual pasteboard
        // items, so retain the historical grouped behavior for promise-based drops.
        // Concrete Finder selections become one shelf row per selected file/item.
        let groups = receivers.isEmpty ? capturedItems.map { [$0] } : [capturedItems]
        var results: [(item: StoredItem, pendingPromises: [NSFilePromiseReceiver])] = []
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
                let item = try writeSnapshot(group, id: directory.id, directoryURL: directory.url)
                results.append((item, receivers))
            }

            if receivers.isEmpty {
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

    private struct CapturedItem {
        let representations: [(type: NSPasteboard.PasteboardType, data: Data?, isPromise: Bool)]
        let stringTitle: String?
    }

    private func capture(_ pasteboardItem: NSPasteboardItem) throws -> CapturedItem {
        let promiseTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)
        var representations: [(NSPasteboard.PasteboardType, Data?, Bool)] = []

        for type in pasteboardItem.types where !type.isContextBoundSourceType {
            if promiseTypes.contains(type.rawValue) {
                representations.append((type, nil, true))
            } else if let data = pasteboardItem.data(forType: type) {
                representations.append((type, data, false))
            } else {
                throw PasteboardSnapshotError.missingData(type.rawValue)
            }
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
        directoryURL: URL
    ) throws -> StoredItem {
        let fileManager = FileManager.default
        let repsDir = directoryURL.appendingPathComponent("reps", isDirectory: true)
        let filesDir = directoryURL.appendingPathComponent("files", isDirectory: true)
        var representations: [RepRecord] = []
        var backingFileNames: [String] = []
        var originPaths: [String: String] = [:]
        var stringTitle: String?
        var repIndex = 0

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
                        fileManager: fileManager
                    )
                    // Take ownership: MOVE the original into the shelf so it leaves
                    // its source. Fall back to copy if the move isn't permitted
                    // (e.g. read-only source or cross-volume restriction) so the drop
                    // still succeeds rather than failing.
                    do {
                        try fileManager.moveItem(at: sourceURL, to: destinationURL)
                        // Remember where it came from so the shelf can put it back.
                        originPaths[destinationURL.lastPathComponent] = sourceURL.path
                    } catch {
                        NSLog("Perch could not move \(sourceURL.path) into shelf (\(error)); copying instead")
                        // Copy fallback: the original is still in place, so no origin
                        // to restore — removing the shelf copy already "puts it back".
                        try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    }
                    backingFileNames.append(destinationURL.lastPathComponent)
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
            originPaths: originPaths.isEmpty ? nil : originPaths
        )
        let metaURL = directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return StoredItem(metadata: metadata, directoryURL: directoryURL)
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
        fileManager: FileManager
    ) -> URL {
        let baseName = fileName.isEmpty ? "file" : fileName
        let initialURL = directory.appendingPathComponent(baseName, isDirectory: false)
        guard fileManager.fileExists(atPath: initialURL.path) else {
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
            if !fileManager.fileExists(atPath: candidateURL.path) {
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
    case holdingMismatch(snapshotterURL: URL, storeURL: URL)
    case invalidFileURL
    case missingData(String)
}
