import Combine
import Foundation
import SmartPerchCore

/// Observable, shelf-lifetime presentation of unresolved Smart Names.
///
/// The authoritative suggestion and decision stay in SQLite; this projection only
/// makes available labels immediately visible in SwiftUI.
@MainActor
final class SmartNameStore: ObservableObject {
    @Published private(set) var suggestionsByItemID: [UUID: AvailableFilenameSuggestion] = [:]

    func suggestion(for itemID: UUID) -> AvailableFilenameSuggestion? {
        suggestionsByItemID[itemID]
    }

    func set(_ suggestion: AvailableFilenameSuggestion) {
        suggestionsByItemID[suggestion.shelfItemID] = suggestion
    }

    func replace(with suggestions: [AvailableFilenameSuggestion]) {
        suggestionsByItemID = Dictionary(
            suggestions.map { ($0.shelfItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @discardableResult
    func remove(for itemID: UUID) -> AvailableFilenameSuggestion? {
        suggestionsByItemID.removeValue(forKey: itemID)
    }
}
