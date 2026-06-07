import AppKit
import UniformTypeIdentifiers

/// RE-VEND: a single object that is simultaneously the file-promise provider, the
/// lazy generic-data provider, and (via the delegate) the on-demand file writer.
/// Subclasses `NSFilePromiseProvider` and *adds* the item's stored generic types
/// on top of the file delivery (Decision F).
///
/// File delivery is **promise-preferred**: the promise is the primary file path
/// (it writes a fresh copy and never exposes the holding-dir master); the concrete
/// holding-dir file URL is offered only as an instant-local convenience. The drag is
/// `.copy`-only (enforced by `ItemDragSource`, Decision K).
final class StoredItemDragWriter: NSFilePromiseProvider {
    private var snapshot: StoredItemDragSnapshot?
    private var retainedDelegate: StoredItemDragWriterDelegate?

    convenience init(item: StoredItem) {
        let delegate = StoredItemDragWriterDelegate(item: item)
        self.init(fileType: delegate.promisedFileType, delegate: delegate)
        snapshot = delegate.snapshot
        retainedDelegate = delegate
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        guard let snapshot else {
            return super.writableTypes(for: pasteboard)
        }

        let providerTypes = super.writableTypes(for: pasteboard)
        let providerTypeSet = Set(providerTypes)
        var types: [NSPasteboard.PasteboardType] = []
        let hasBackingFile = !snapshot.backingFileURLs.isEmpty
        if hasBackingFile {
            types.append(contentsOf: providerTypes)
            types.append(.fileURL)
        }

        for record in snapshot.representations where !record.isPromisePlaceholder {
            let type = NSPasteboard.PasteboardType(record.typeIdentifier)
            if type == .fileURL, hasBackingFile {
                continue
            }
            if providerTypeSet.contains(type) || isFilePromiseControlType(type) {
                continue
            }
            types.append(type)
        }

        return types.removingDuplicates()
    }

    override func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        if super.writableTypes(for: pasteboard).contains(type) {
            return super.writingOptions(forType: type, pasteboard: pasteboard)
        }

        if type == .fileURL {
            return []
        }

        if type == .string {
            return []
        }

        return .promised
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard let snapshot else {
            return super.pasteboardPropertyList(forType: type)
        }

        if isFilePromiseControlType(type) {
            return super.pasteboardPropertyList(forType: type)
        }

        if type == .fileURL, let backingFileURL = snapshot.backingFileURLs.first {
            return (backingFileURL as NSURL).pasteboardPropertyList(forType: .fileURL)
        }

        guard let data = snapshot.data(forType: type) else {
            return super.pasteboardPropertyList(forType: type)
        }

        if type == .string, let string = String(data: data, encoding: .utf8) {
            return string
        }

        return data
    }
}

/// Supplies the promised filename and writes the file from the holding dir, off
/// the main actor on its own operation queue.
final class StoredItemDragWriterDelegate: NSObject, NSFilePromiseProviderDelegate {
    fileprivate let snapshot: StoredItemDragSnapshot
    private let operationQueue: OperationQueue
    fileprivate let promisedFileType: String

    init(item: StoredItem) {
        snapshot = MainActor.assumeIsolated {
            StoredItemDragSnapshot(item: item)
        }
        operationQueue = OperationQueue()
        operationQueue.name = "Perch.StoredItemDragWriter"
        operationQueue.maxConcurrentOperationCount = 1
        promisedFileType = snapshot.backingFileURLs.first?.filePromiseTypeIdentifier ?? UTType.data.identifier
        super.init()
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        snapshot.backingFileURLs.first?.lastPathComponent ?? "\(snapshot.title).dat"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let sourceURL = snapshot.backingFileURLs.first else {
            completionHandler(StoredItemDragWriterError.noBackingFile)
            return
        }

        let fileManager = FileManager.default
        let destinationURL = promisedDestinationURL(
            promiseURL: url,
            fileName: sourceURL.lastPathComponent,
            fileManager: fileManager
        )
        do {
            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: destinationURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                throw StoredItemDragWriterError.destinationIsDirectory(destinationURL)
            }

            try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
            NSLog("Perch promised file wrote \(sourceURL.lastPathComponent) to \(destinationURL.path)")
            completionHandler(nil)
        } catch {
            NSLog("Perch promised file write failed for \(sourceURL.lastPathComponent) to \(destinationURL.path): \(error)")
            completionHandler(error)
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        operationQueue
    }
}

private enum StoredItemDragWriterError: Error {
    case noBackingFile
    case destinationIsDirectory(URL)
}

private func isFilePromiseControlType(_ type: NSPasteboard.PasteboardType) -> Bool {
    let identifier = type.rawValue
    return identifier == "com.apple.NSFilePromiseItemMetaData"
        || identifier == "com.apple.pasteboard.NSFilePromiseID"
        || identifier.hasPrefix("com.apple.pasteboard.promised-")
        || NSFilePromiseReceiver.readableDraggedTypes.contains(identifier)
}

private func promisedDestinationURL(
    promiseURL: URL,
    fileName: String,
    fileManager: FileManager
) -> URL {
    var isDirectory = ObjCBool(false)
    if fileManager.fileExists(atPath: promiseURL.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
        return uniqueDestinationURL(for: fileName, in: promiseURL, fileManager: fileManager)
    }

    if promiseURL.hasDirectoryPath {
        return uniqueDestinationURL(for: fileName, in: promiseURL, fileManager: fileManager)
    }

    return promiseURL
}

private func uniqueDestinationURL(
    for fileName: String,
    in directoryURL: URL,
    fileManager: FileManager
) -> URL {
    let baseName = fileName.isEmpty ? "file" : fileName
    let initialURL = directoryURL.appendingPathComponent(baseName, isDirectory: false)
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

        let candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false)
        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        suffix += 1
    }
}

private struct StoredItemDragSnapshot {
    let title: String
    let representations: [RepRecord]
    let backingFileURLs: [URL]
    private let representationFileURLsByType: [String: URL]

    @MainActor
    init(item: StoredItem) {
        title = item.metadata.title
        representations = item.metadata.representations
        backingFileURLs = item.backingFileURLs()

        let repsDir = item.directoryURL.appendingPathComponent("reps", isDirectory: true)
        var fileURLsByType: [String: URL] = [:]
        for record in item.metadata.representations where !record.isPromisePlaceholder {
            guard fileURLsByType[record.typeIdentifier] == nil else {
                continue
            }
            fileURLsByType[record.typeIdentifier] = repsDir.appendingPathComponent(
                record.fileName,
                isDirectory: false
            )
        }
        representationFileURLsByType = fileURLsByType
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        guard let fileURL = representationFileURLsByType[type.rawValue] else {
            return nil
        }
        return try? Data(contentsOf: fileURL)
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension URL {
    var filePromiseTypeIdentifier: String {
        let identifier = (try? resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
            ?? UTType(filenameExtension: pathExtension)?.identifier
            ?? UTType.data.identifier

        if identifier == "public.plain-text" {
            return NSPasteboard.PasteboardType.string.rawValue
        }
        return identifier
    }
}
