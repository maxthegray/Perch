import Foundation
import XCTest
@testable import SmartPerchCore

final class RouteSuggestionMatcherTests: XCTestCase {
    func testMatchesAnItemToThePatternLearnedForItsOwnContext() {
        let itemID = UUID()
        let suggestions = RouteSuggestionMatcher().suggestions(
            forItemContexts: [
                itemID: RouteLearningContext(
                    sourceAppBundleIdentifier: "com.apple.Safari",
                    sourceAppName: "Safari",
                    category: .document
                )
            ],
            patterns: [pattern(destination: documents)]
        )

        XCTAssertEqual(suggestions[itemID]?.destination, documents)
        XCTAssertEqual(suggestions[itemID]?.occurrenceCount, 4)
        XCTAssertEqual(suggestions[itemID]?.destinationShare, 1)
    }

    func testDoesNotOfferAPatternFromAnotherSourceOrCategory() {
        let otherApp = UUID()
        let otherCategory = UUID()

        let suggestions = RouteSuggestionMatcher().suggestions(
            forItemContexts: [
                otherApp: RouteLearningContext(
                    sourceAppBundleIdentifier: "com.apple.mail",
                    sourceAppName: "Mail",
                    category: .document
                ),
                otherCategory: RouteLearningContext(
                    sourceAppBundleIdentifier: "com.apple.Safari",
                    sourceAppName: "Safari",
                    category: .image
                )
            ],
            patterns: [pattern(destination: documents)]
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    /// macOS offers no way to synthesize a drop into another app's window, so an
    /// application route is knowledge Perch holds but cannot act on.
    func testApplicationDestinationsAreNotOffered() {
        let itemID = UUID()
        let suggestions = RouteSuggestionMatcher().suggestions(
            forItemContexts: [itemID: safariDocuments],
            patterns: [
                pattern(
                    destination: .application(
                        bundleIdentifier: "com.apple.mail",
                        name: "Mail"
                    )
                )
            ]
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    /// A context can hold more than one pattern once an old destination falls out of
    /// favor; the offer must be the strongest, not whichever arrived first.
    func testPrefersTheStrongerOfTwoPatternsForOneContext() {
        let itemID = UUID()
        let suggestions = RouteSuggestionMatcher().suggestions(
            forItemContexts: [itemID: safariDocuments],
            patterns: [
                pattern(destination: desktop, occurrenceCount: 3, share: 0.76),
                pattern(destination: documents, occurrenceCount: 9, share: 0.95)
            ]
        )

        XCTAssertEqual(suggestions[itemID]?.destination, documents)
    }

    func testAnItemWithNoLearnedRouteGetsNoOffer() {
        XCTAssertTrue(
            RouteSuggestionMatcher().suggestions(
                forItemContexts: [UUID(): safariDocuments],
                patterns: []
            ).isEmpty
        )
    }

    /// The matcher and the detector must agree on what counts as the same context, or a
    /// learned pattern would never reach the item that produced it.
    func testMatchesTheContextTheDetectorItselfLearned() {
        let itemID = UUID()
        let sessions = (0..<3).map { _ in
            ItemRouteEvent(
                routeSessionID: UUID(),
                shelfItemID: UUID(),
                successfulDropAtMilliseconds: 1_700_000_000_000,
                dwellTimeMilliseconds: 5_000,
                destination: documents,
                captureMethod: .filePromiseWrite,
                transferMode: .move,
                sourceAppBundleIdentifier: "com.apple.Safari",
                sourceAppName: "Safari",
                category: .document
            )
        }

        let suggestions = RouteSuggestionMatcher().suggestions(
            forItemContexts: [itemID: safariDocuments],
            patterns: RoutePatternDetector().detectPatterns(in: sessions)
        )

        XCTAssertEqual(suggestions[itemID]?.destination, documents)
    }

    private let documents = RouteDestination.folder(path: "/Users/test/Documents")
    private let desktop = RouteDestination.folder(path: "/Users/test/Desktop")
    private let safariDocuments = RouteLearningContext(
        sourceAppBundleIdentifier: "com.apple.Safari",
        sourceAppName: "Safari",
        category: .document
    )

    private func pattern(
        destination: RouteDestination,
        occurrenceCount: Int = 4,
        share: Double = 1
    ) -> LearnedRoutePattern {
        LearnedRoutePattern(
            sourceAppBundleIdentifier: "com.apple.Safari",
            sourceAppName: "Safari",
            category: .document,
            destination: destination,
            occurrenceCount: occurrenceCount,
            contextSessionCount: occurrenceCount,
            destinationShare: share
        )
    }
}
