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

    /// How long a promise source gets to deliver before the drop is completed with
    /// whatever arrived. Without this, a source that never calls back (or a receiver
    /// whose callback count doesn't match its `fileTypes`) strands the drop forever —
    /// the item is only inserted after `completion`, so it silently never appears.
    private static let deliveryTimeout: TimeInterval = 30

    /// Callback bookkeeping, mutated only on the serial `operationQueue` (receiver
    /// callbacks and the timeout both land there), so access is serialized.
    private final class MaterializeState: @unchecked Sendable {
        var remaining: Int
        var urls: [URL] = []
        var finished = false
        init(remaining: Int) { self.remaining = remaining }
    }

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
        // One reader callback per promised file. A receiver with an empty `fileTypes`
        // never calls the reader at all, so it must contribute zero — counting it as
        // one (the old `max(count, 1)`) left `remaining` stuck above zero forever.
        let expectedCallbacks = receivers.reduce(0) { partial, receiver in
            partial + receiver.fileTypes.count
        }
        guard expectedCallbacks > 0 else {
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

        let state = MaterializeState(remaining: expectedCallbacks)
        let queue = operationQueue

        // Runs on `queue`; delivers exactly once.
        let finish: (String?) -> Void = { reason in
            guard !state.finished else { return }
            state.finished = true
            if let reason {
                NSLog("Perch promise materialization \(reason); storing \(state.urls.count) delivered file(s)")
            }
            completion(state.urls)
        }

        for receiver in receivers where !receiver.fileTypes.isEmpty {
            receiver.receivePromisedFiles(
                atDestination: filesDir,
                options: [:],
                operationQueue: queue
            ) { fileURL, error in
                if error == nil {
                    state.urls.append(fileURL)
                }

                state.remaining -= 1
                if state.remaining <= 0 {
                    finish(nil)
                }
            }
        }

        // Belt and braces: even a well-counted receiver can simply never call back
        // (the source app hung or quit mid-drag). Complete with what we have.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.deliveryTimeout) {
            queue.addOperation {
                finish("timed out")
            }
        }
    }
}
