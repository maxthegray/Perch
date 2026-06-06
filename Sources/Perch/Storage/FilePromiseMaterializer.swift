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
        self.operationQueue = OperationQueue()
    }

    func materialize(
        _ receivers: [NSFilePromiseReceiver],
        into filesDir: URL,
        completion: @escaping ([URL]) -> Void
    ) {
        fatalError("unimplemented")
    }
}
