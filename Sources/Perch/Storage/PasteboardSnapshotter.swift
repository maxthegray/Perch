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
        let directory = store.newItemDirectory()
        let expectedDirectoryURL = holding.itemDir(directory.id)
        guard directory.url == expectedDirectoryURL else {
            throw PasteboardSnapshotError.holdingMismatch(
                snapshotterURL: expectedDirectoryURL,
                storeURL: directory.url
            )
        }

        do {
            let result = try snapshotPasteboardItems(
                pasteboard.pasteboardItems ?? [],
                pasteboard: pasteboard,
                id: directory.id,
                directoryURL: directory.url
            )
            store.insert(result.item, at: nil)
            return result
        } catch {
            try? FileManager.default.removeItem(at: directory.url)
            throw error
        }
    }

    private func snapshotPasteboardItems(
        _ pasteboardItems: [NSPasteboardItem],
        pasteboard: NSPasteboard,
        id: UUID,
        directoryURL: URL
    ) throws -> (item: StoredItem, pendingPromises: [NSFilePromiseReceiver]) {
        let fileManager = FileManager.default
        let repsDir = directoryURL.appendingPathComponent("reps", isDirectory: true)
        let filesDir = directoryURL.appendingPathComponent("files", isDirectory: true)
        let promiseTypeIdentifiers = Set(NSFilePromiseReceiver.readableDraggedTypes)
        let pendingPromises = pasteboard.readObjects(
            forClasses: [NSFilePromiseReceiver.self],
            options: nil
        ) as? [NSFilePromiseReceiver] ?? []

        var representations: [RepRecord] = []
        var backingFileNames: [String] = []
        var stringTitle: String?
        var repIndex = 0

        for pasteboardItem in pasteboardItems {
            if stringTitle == nil,
               let title = pasteboardItem.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                stringTitle = title
            }

            for type in pasteboardItem.types {
                let fileName = "rep-\(repIndex).dat"
                repIndex += 1

                if promiseTypeIdentifiers.contains(type.rawValue) {
                    representations.append(
                        RepRecord(
                            typeIdentifier: type.rawValue,
                            fileName: fileName,
                            isPromisePlaceholder: true
                        )
                    )
                } else if let data = pasteboardItem.data(forType: type) {
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
                    let sourceURL = try fileURL(from: pasteboardItem, data: pasteboardItem.data(forType: type))
                    let destinationURL = uniqueDestinationURL(
                        for: sourceURL.lastPathComponent,
                        in: filesDir,
                        fileManager: fileManager
                    )
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
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
            primaryFileType: representations.first?.typeIdentifier
        )
        let metaURL = directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return (
            StoredItem(metadata: metadata, directoryURL: directoryURL),
            pendingPromises
        )
    }

    private func fileURL(from pasteboardItem: NSPasteboardItem, data: Data?) throws -> URL {
        if let string = pasteboardItem.string(forType: .fileURL),
           let url = URL(string: string),
           url.isFileURL {
            return url
        }

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
    case holdingMismatch(snapshotterURL: URL, storeURL: URL)
    case invalidFileURL
    case missingData(String)
}
