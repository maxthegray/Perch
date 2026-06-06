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
        fatalError("unimplemented")
    }

    /// Insert an item at `index` (nil = front) and update `index.json`.
    func insert(_ item: StoredItem, at index: Int?) {
        fatalError("unimplemented")
    }

    /// Remove an item and delete its `items/<uuid>/` directory.
    func remove(_ item: StoredItem) {
        fatalError("unimplemented")
    }

    /// Create a fresh `items/<uuid>/{reps,files}` directory and return its id + url.
    func newItemDirectory() -> (id: UUID, url: URL) {
        fatalError("unimplemented")
    }
}
