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
        lateDelivery: @escaping (URL) -> Void,
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
            var delivered = state.urls
            if let reason {
                // A receiver that never called back may still have written its file.
                // Adopt whatever actually landed, or those bytes sit in the item's
                // `files/` directory with no entry in `backingFileNames` — invisible
                // to the shelf and unreachable by every vend path.
                delivered = Self.includingUnreportedFiles(in: filesDir, alreadyDelivered: delivered)
                NSLog("Perch promise materialization \(reason); storing \(delivered.count) delivered file(s)")
            }
            completion(delivered)
        }

        for receiver in receivers where !receiver.fileTypes.isEmpty {
            receiver.receivePromisedFiles(
                atDestination: filesDir,
                options: [:],
                operationQueue: queue
            ) { fileURL, error in
                if error == nil {
                    if state.finished {
                        // The timeout already completed the drop. Surface this file
                        // separately so the caller can append it to the now-visible
                        // shelf item instead of leaving invisible bytes behind.
                        lateDelivery(fileURL)
                    } else {
                        state.urls.append(fileURL)
                    }
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

    /// `alreadyDelivered` plus any other file already sitting in `filesDir` when the
    /// timeout fires. A later successful callback travels through `lateDelivery`.
    private static func includingUnreportedFiles(
        in filesDir: URL,
        alreadyDelivered: [URL]
    ) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: filesDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return alreadyDelivered }

        let deliveredNames = Set(alreadyDelivered.map(\.lastPathComponent))
        return alreadyDelivered + entries.filter {
            !deliveredNames.contains($0.lastPathComponent)
        }
    }
}

/// Orders the materializer's initial completion and late-delivery callbacks after
/// both hop from its operation queue to the main actor. An early late-delivery task
/// can run before the initial-completion task, so it waits here and joins that first
/// batch; later files can be appended to the already-visible item immediately.
@MainActor
final class PromiseMaterializationReconciler {
    private var handledInitialCompletion = false
    private var queuedLateURLs: [URL] = []

    func reconcileInitial(_ urls: [URL]) -> [URL] {
        handledInitialCompletion = true
        defer { queuedLateURLs.removeAll() }
        return Self.removingDuplicatePaths(from: urls + queuedLateURLs)
    }

    /// Nil means the initial completion has not reached the main actor yet, so this
    /// URL was queued and will be returned by `reconcileInitial(_:)`.
    func reconcileLate(_ url: URL) -> URL? {
        guard handledInitialCompletion else {
            queuedLateURLs.append(url)
            return nil
        }
        return url
    }

    private static func removingDuplicatePaths(from urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        return urls.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }
}
