import Foundation

/// A learned pattern matched to an item currently sitting on the shelf, i.e. an offer
/// to finish a trip the user has already made several times from this source.
public struct SuggestedRoute: Equatable, Sendable {
    public let shelfItemID: UUID
    public let destination: RouteDestination
    public let occurrenceCount: Int
    public let destinationShare: Double

    public init(
        shelfItemID: UUID,
        destination: RouteDestination,
        occurrenceCount: Int,
        destinationShare: Double
    ) {
        self.shelfItemID = shelfItemID
        self.destination = destination
        self.occurrenceCount = occurrenceCount
        self.destinationShare = destinationShare
    }
}

/// Pairs shelf items with learned patterns. Pure and database-free, like the detector.
public struct RouteSuggestionMatcher: Sendable {
    /// Destination kinds Perch can actually carry out on the user's behalf.
    ///
    /// Folders are a plain file move. An application destination is *not* actionable:
    /// macOS gives no way to synthesize a drop into another app's window, and opening
    /// the file in that app is a different action from the one the user was observed
    /// performing. Those patterns keep accumulating; they are simply not offered.
    public let actionableDestinationKinds: Set<RouteDestinationKind>

    public init(
        actionableDestinationKinds: Set<RouteDestinationKind> = [.folder]
    ) {
        self.actionableDestinationKinds = actionableDestinationKinds
    }

    /// The best actionable destination for each item that has one. Patterns arrive
    /// already sorted by confidence, so the first actionable match for a context wins.
    public func suggestions(
        forItemContexts contexts: [UUID: RouteLearningContext],
        patterns: [LearnedRoutePattern]
    ) -> [UUID: SuggestedRoute] {
        guard !contexts.isEmpty, !patterns.isEmpty else { return [:] }

        var bestPatternByContext: [LearningContextKey: LearnedRoutePattern] = [:]
        for pattern in patterns
        where actionableDestinationKinds.contains(pattern.destination.kind) {
            let key = LearningContextKey(pattern: pattern)
            guard let incumbent = bestPatternByContext[key] else {
                bestPatternByContext[key] = pattern
                continue
            }
            if Self.isStronger(pattern, than: incumbent) {
                bestPatternByContext[key] = pattern
            }
        }
        guard !bestPatternByContext.isEmpty else { return [:] }

        var suggestions: [UUID: SuggestedRoute] = [:]
        for (shelfItemID, context) in contexts {
            guard let pattern = bestPatternByContext[LearningContextKey(context: context)]
            else {
                continue
            }
            suggestions[shelfItemID] = SuggestedRoute(
                shelfItemID: shelfItemID,
                destination: pattern.destination,
                occurrenceCount: pattern.occurrenceCount,
                destinationShare: pattern.destinationShare
            )
        }
        return suggestions
    }

    /// Mirrors the detector's own ordering so the matcher does not silently disagree
    /// with it about which of two patterns is the more confident.
    private static func isStronger(
        _ lhs: LearnedRoutePattern,
        than rhs: LearnedRoutePattern
    ) -> Bool {
        if lhs.destinationShare != rhs.destinationShare {
            return lhs.destinationShare > rhs.destinationShare
        }
        if lhs.occurrenceCount != rhs.occurrenceCount {
            return lhs.occurrenceCount > rhs.occurrenceCount
        }
        return lhs.destination.normalizedIdentifier
            < rhs.destination.normalizedIdentifier
    }
}
