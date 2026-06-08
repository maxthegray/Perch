import Foundation

/// Which screen edges the user has enabled for shelf docks (Left / Right / Top-notch).
/// Persisted to `UserDefaults`; `onChange` lets the controller reinstall the edge tabs
/// when the selection changes. At least one edge always stays enabled so the shelf can
/// never become unreachable.
@MainActor
final class EdgeSettings {
    private static let key = "Perch.EnabledEdges"

    /// Called after the selection changes (and has been persisted).
    var onChange: (() -> Void)?

    private(set) var enabledEdges: Set<ShelfEdge> {
        didSet {
            UserDefaults.standard.set(enabledEdges.map(\.rawValue), forKey: Self.key)
            onChange?()
        }
    }

    init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            let edges = Set(raw.compactMap(ShelfEdge.init(rawValue:)))
            enabledEdges = edges.isEmpty ? Set(ShelfEdge.allCases) : edges
        } else {
            enabledEdges = Set(ShelfEdge.allCases)
        }
    }

    func isEnabled(_ edge: ShelfEdge) -> Bool {
        enabledEdges.contains(edge)
    }

    func toggle(_ edge: ShelfEdge) {
        if enabledEdges.contains(edge) {
            guard enabledEdges.count > 1 else { return }  // keep at least one
            enabledEdges.remove(edge)
        } else {
            enabledEdges.insert(edge)
        }
    }
}
