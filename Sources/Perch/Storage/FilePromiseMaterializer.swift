import AppKit

/// STORE: drives `NSFilePromiseReceiver`s, writing promised files into an item's
/// `files/` directory off the main actor.
///
/// NOTE: `completion` fires on `operationQueue` (OFF the main actor). Callers that
/// then mutate `ItemStore` (`@MainActor` + `@Published`) MUST hop to the main actor
/// first (Decision-adjacent requirement; see RISKS §3 and T7).
@MainActor
final class FilePromiseMaterializer {
    let operationQueue: OperationQueue

    init() {
        operationQueue = OperationQueue()
        operationQueue.name = "Perch.FilePromiseMaterializer"
        operationQueue.maxConcurrentOperationCount = 1
    }

    func materialize(
        _ receivers: [NSFilePromiseReceiver],
        into filesDir: URL,
        completion: @escaping ([URL]) -> Void
    ) {
        guard !receivers.isEmpty else {
            operationQueue.addOperation {
                completion([])
            }
            return
        }

        do {
            try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        } catch {
            operationQueue.addOperation {
                completion([])
            }
            return
        }

        let expectedCallbacks = receivers.reduce(0) { partial, receiver in
            partial + max(receiver.fileTypes.count, 1)
        }
        var remainingCallbacks = expectedCallbacks
        var materializedURLs: [URL] = []

        for receiver in receivers {
            receiver.receivePromisedFiles(
                atDestination: filesDir,
                options: [:],
                operationQueue: operationQueue
            ) { fileURL, error in
                if error == nil {
                    materializedURLs.append(fileURL)
                }

                remainingCallbacks -= 1
                if remainingCallbacks == 0 {
                    completion(materializedURLs)
                }
            }
        }
    }
}
