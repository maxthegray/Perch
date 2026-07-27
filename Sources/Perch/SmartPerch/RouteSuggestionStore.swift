import Combine
import Foundation
import SmartPerchCore

/// Observable, shelf-lifetime projection of the learned routes that apply to the items
/// currently on the shelf.
///
/// The route history and the patterns derived from it live in SQLite; this only holds
/// the matched offer so SwiftUI can draw it. Mirrors `SmartNameStore`.
@MainActor
final class RouteSuggestionStore: ObservableObject {
    @Published private(set) var suggestionsByItemID: [UUID: SuggestedRoute] = [:]
    /// Items the user waved off. A dismissal lasts as long as the item is on the shelf,
    /// so a refresh cannot bring the same offer back a second later.
    private var dismissedItemIDs: Set<UUID> = []
    /// Items whose files are being moved right now. Their offer is withdrawn so a
    /// double-click cannot file the same item twice.
    private var filingItemIDs: Set<UUID> = []

    func suggestion(for itemID: UUID) -> SuggestedRoute? {
        suggestionsByItemID[itemID]
    }

    func replace(with suggestions: [UUID: SuggestedRoute]) {
        let offered = suggestions.filter {
            !dismissedItemIDs.contains($0.key) && !filingItemIDs.contains($0.key)
        }
        guard offered != suggestionsByItemID else { return }
        suggestionsByItemID = offered
    }

    func dismiss(_ itemID: UUID) {
        dismissedItemIDs.insert(itemID)
        suggestionsByItemID.removeValue(forKey: itemID)
    }

    func beginFiling(_ itemID: UUID) {
        filingItemIDs.insert(itemID)
        suggestionsByItemID.removeValue(forKey: itemID)
    }

    func endFiling(_ itemID: UUID) {
        filingItemIDs.remove(itemID)
    }

    /// Drop state for items that have left the shelf, so a recycled id cannot inherit a
    /// stale dismissal.
    func retainSuggestions(for itemIDs: Set<UUID>) {
        let retained = suggestionsByItemID.filter { itemIDs.contains($0.key) }
        if retained.count != suggestionsByItemID.count {
            suggestionsByItemID = retained
        }
        dismissedItemIDs.formIntersection(itemIDs)
        filingItemIDs.formIntersection(itemIDs)
    }
}
