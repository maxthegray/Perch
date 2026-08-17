import Combine
import Foundation
import SmartPerchCore

/// Observable, shelf-lifetime presentation of unresolved Smart Names.
///
/// The authoritative suggestion and decision stay in SQLite; this projection only
/// makes available labels immediately visible in SwiftUI.
@MainActor
final class SmartNameStore: ObservableObject {
    @Published var isEnabled = true
    @Published private(set) var suggestionsByItemID: [UUID: AvailableFilenameSuggestion] = [:]
    /// A generated ghost label carried across adoption until the persisted suggestion
    /// for the new shelf item is ready. This keeps the row's presentation continuous.
    @Published private(set) var provisionalNamesByItemID: [UUID: String] = [:]
    /// Screenshot rows use a stable placeholder while their name is unresolved. This set
    /// survives completion without a suggestion so a low-information capture keeps the
    /// useful generic "Screenshot" label instead of jumping back to a timestamp.
    @Published private(set) var screenshotItemIDs: Set<UUID> = []
    @Published private(set) var analyzingItemIDs: Set<UUID> = []

    struct NamePresentation: Equatable {
        let title: String
        let isAnalyzing: Bool
    }

    func suggestion(for itemID: UUID) -> AvailableFilenameSuggestion? {
        guard isEnabled else { return nil }
        return suggestionsByItemID[itemID]
    }

    func presentation(
        for itemID: UUID,
        originalTitle: String
    ) -> NamePresentation {
        // With Smart Perch off a row is just its filename: no generated name, no
        // "Screenshot" placeholder, and no analysis spinner for work the user cannot see.
        guard isEnabled else {
            return NamePresentation(
                title: originalTitle,
                isAnalyzing: false
            )
        }
        if let suggestion = suggestion(for: itemID) {
            return NamePresentation(
                title: suggestion.displayName,
                isAnalyzing: analyzingItemIDs.contains(itemID)
            )
        }
        if let provisionalName = provisionalNamesByItemID[itemID] {
            return NamePresentation(
                title: provisionalName,
                isAnalyzing: analyzingItemIDs.contains(itemID)
            )
        }
        if screenshotItemIDs.contains(itemID) {
            return NamePresentation(
                title: ScreenshotNamePresentation.placeholder,
                isAnalyzing: analyzingItemIDs.contains(itemID)
            )
        }
        return NamePresentation(
            title: originalTitle,
            isAnalyzing: analyzingItemIDs.contains(itemID)
        )
    }

    func registerScreenshot(_ itemID: UUID) {
        screenshotItemIDs.insert(itemID)
    }

    func beginAnalyzingScreenshot(_ itemID: UUID) {
        screenshotItemIDs.insert(itemID)
        analyzingItemIDs.insert(itemID)
    }

    func beginAnalyzing(_ itemID: UUID) {
        analyzingItemIDs.insert(itemID)
    }

    func finishAnalyzingScreenshot(_ itemID: UUID) {
        analyzingItemIDs.remove(itemID)
    }

    func finishAnalyzing(_ itemID: UUID) {
        analyzingItemIDs.remove(itemID)
    }

    func isRegisteredScreenshot(_ itemID: UUID) -> Bool {
        screenshotItemIDs.contains(itemID)
    }

    func setProvisionalName(_ name: String, for itemID: UUID) {
        provisionalNamesByItemID[itemID] = name
    }

    func retainPresentations(for itemIDs: Set<UUID>) {
        let retainedSuggestions = suggestionsByItemID.filter { itemIDs.contains($0.key) }
        if retainedSuggestions.count != suggestionsByItemID.count {
            suggestionsByItemID = retainedSuggestions
        }
        let retainedProvisionalNames = provisionalNamesByItemID.filter {
            itemIDs.contains($0.key)
        }
        if retainedProvisionalNames.count != provisionalNamesByItemID.count {
            provisionalNamesByItemID = retainedProvisionalNames
        }
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
        provisionalNamesByItemID.removeValue(forKey: suggestion.shelfItemID)
    }

    func replace(with suggestions: [AvailableFilenameSuggestion]) {
        suggestionsByItemID = Dictionary(
            suggestions.map { ($0.shelfItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        provisionalNamesByItemID = provisionalNamesByItemID.filter {
            suggestionsByItemID[$0.key] == nil
        }
    }

    @discardableResult
    func remove(for itemID: UUID) -> AvailableFilenameSuggestion? {
        analyzingItemIDs.remove(itemID)
        screenshotItemIDs.remove(itemID)
        provisionalNamesByItemID.removeValue(forKey: itemID)
        return suggestionsByItemID.removeValue(forKey: itemID)
    }

    func remove(for itemID: UUID, ifFileIDMatches fileID: UUID) {
        guard suggestionsByItemID[itemID]?.fileID == fileID else { return }
        suggestionsByItemID.removeValue(forKey: itemID)
    }

    func clearSuggestion(for itemID: UUID) {
        suggestionsByItemID.removeValue(forKey: itemID)
    }

    /// Forget everything when Smart Perch is switched off. The generated names are not
    /// worth preserving across a teardown: nothing is producing them any more, and the
    /// "Screenshot" placeholder would otherwise outlive the feature that replaces it.
    func reset() {
        guard !suggestionsByItemID.isEmpty
                || !provisionalNamesByItemID.isEmpty
                || !screenshotItemIDs.isEmpty
                || !analyzingItemIDs.isEmpty
        else { return }
        suggestionsByItemID = [:]
        provisionalNamesByItemID = [:]
        screenshotItemIDs = []
        analyzingItemIDs = []
    }
}
