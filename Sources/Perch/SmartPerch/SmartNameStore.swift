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
    /// Screenshot rows use one stable presentation from their first frame onward. This
    /// set survives completion without a suggestion so a low-information capture keeps
    /// the useful generic "Screenshot" label instead of jumping back to a timestamp.
    @Published private(set) var screenshotItemIDs: Set<UUID> = []
    @Published private(set) var analyzingItemIDs: Set<UUID> = []

    struct NamePresentation: Equatable {
        let title: String
        let isAnalyzing: Bool
        let usesStableWidth: Bool
    }

    func suggestion(for itemID: UUID) -> AvailableFilenameSuggestion? {
        suggestionsByItemID[itemID]
    }

    func presentation(
        for itemID: UUID,
        originalTitle: String
    ) -> NamePresentation {
        if let suggestion = suggestion(for: itemID) {
            return NamePresentation(
                title: suggestion.displayName,
                isAnalyzing: analyzingItemIDs.contains(itemID),
                usesStableWidth: screenshotItemIDs.contains(itemID)
            )
        }
        if screenshotItemIDs.contains(itemID) {
            return NamePresentation(
                title: ScreenshotNamePresentation.placeholder,
                isAnalyzing: analyzingItemIDs.contains(itemID),
                usesStableWidth: true
            )
        }
        return NamePresentation(
            title: originalTitle,
            isAnalyzing: false,
            usesStableWidth: false
        )
    }

    func registerScreenshot(_ itemID: UUID) {
        screenshotItemIDs.insert(itemID)
    }

    func beginAnalyzingScreenshot(_ itemID: UUID) {
        screenshotItemIDs.insert(itemID)
        analyzingItemIDs.insert(itemID)
    }

    func finishAnalyzingScreenshot(_ itemID: UUID) {
        analyzingItemIDs.remove(itemID)
    }

    func retainPresentations(for itemIDs: Set<UUID>) {
        let retainedScreenshots = screenshotItemIDs.intersection(itemIDs)
        if retainedScreenshots != screenshotItemIDs {
            screenshotItemIDs = retainedScreenshots
        }
        let retainedAnalysis = analyzingItemIDs.intersection(itemIDs)
        if retainedAnalysis != analyzingItemIDs {
            analyzingItemIDs = retainedAnalysis
        }
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
        analyzingItemIDs.remove(itemID)
        screenshotItemIDs.remove(itemID)
        return suggestionsByItemID.removeValue(forKey: itemID)
    }
}
