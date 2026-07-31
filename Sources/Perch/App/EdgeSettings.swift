import Combine
import Foundation

/// Which screen edges the user has enabled for shelf docks (Left / Right / Top-notch).
/// Persisted to `UserDefaults`; `onChange` lets the controller reinstall the edge tabs
/// when the selection changes, and `ObservableObject` lets the Settings window's
/// toggles stay live. At least one edge always stays enabled so the shelf can never
/// become unreachable.
@MainActor
final class EdgeSettings: ObservableObject {
    private static let key = PerchSettings.enabledEdges

    /// Called after the selection changes (and has been persisted).
    var onChange: (() -> Void)?

    @Published private(set) var enabledEdges: Set<ShelfEdge> {
        didSet {
            UserDefaults.standard.set(enabledEdges.map(\.rawValue), forKey: Self.key)
            onChange?()
        }
    }

    /// Fresh installs expose both reachable side docks; the notch remains opt-in.
    private static let defaultEdges: Set<ShelfEdge> = [.left, .right]

    init() {
        if let raw = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            let edges = Set(raw.compactMap(ShelfEdge.init(rawValue:)))
            enabledEdges = edges.isEmpty ? Self.defaultEdges : edges
        } else {
            enabledEdges = Self.defaultEdges
        }
    }

    func isEnabled(_ edge: ShelfEdge) -> Bool {
        enabledEdges.contains(edge)
    }

    /// Replace the whole selection at once — the first-run edge picker hands over its
    /// answer in one go rather than as a sequence of toggles, which would fire `onChange`
    /// (and rebuild every edge tab) once per edge. An empty set is refused for the same
    /// reason `toggle` refuses to remove the last edge: the shelf must stay reachable.
    func setEnabledEdges(_ edges: Set<ShelfEdge>) {
        guard !edges.isEmpty, edges != enabledEdges else { return }
        enabledEdges = edges
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
