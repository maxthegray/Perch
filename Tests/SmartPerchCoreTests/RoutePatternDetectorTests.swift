import Foundation
import XCTest
@testable import SmartPerchCore

final class RoutePatternDetectorTests: XCTestCase {
    func testRequiresThreeDistinctSessionsAndDeduplicatesBatchItems() {
        let firstSession = UUID()
        let routes = [
            route(sessionID: firstSession),
            route(sessionID: firstSession),
            route(),
        ]

        XCTAssertEqual(RoutePatternDetector().detectPatterns(in: routes), [])

        let patterns = RoutePatternDetector().detectPatterns(
            in: routes + [route()]
        )
        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns[0].occurrenceCount, 3)
        XCTAssertEqual(patterns[0].contextSessionCount, 3)
        XCTAssertEqual(patterns[0].destinationShare, 1)
    }

    func testRequiresSeventyFivePercentDestinationShare() {
        let dominant = (0..<3).map { _ in route(destination: documents) }
        let fourSessions = dominant + [route(destination: desktop)]
        let learned = RoutePatternDetector().detectPatterns(in: fourSessions)

        XCTAssertEqual(learned.count, 1)
        XCTAssertEqual(learned[0].destination, documents)
        XCTAssertEqual(learned[0].destinationShare, 0.75)

        XCTAssertEqual(
            RoutePatternDetector().detectPatterns(
                in: fourSessions + [route(destination: desktop)]
            ),
            []
        )
    }

    func testSourceApplicationAndCategoryContextsStaySeparate() {
        let documentRoutes = (0..<3).map { _ in
            route(category: .document, destination: documents)
        }
        let imageRoutes = (0..<3).map { _ in
            route(category: .image, destination: desktop)
        }
        let mailRoutes = (0..<3).map { _ in
            route(
                sourceBundleIdentifier: "com.apple.mail",
                sourceName: "Mail",
                category: .document,
                destination: desktop
            )
        }

        let patterns = RoutePatternDetector().detectPatterns(
            in: documentRoutes + imageRoutes + mailRoutes
        )

        XCTAssertEqual(patterns.count, 3)
        XCTAssertTrue(patterns.contains {
            $0.sourceAppBundleIdentifier == "com.apple.Safari"
                && $0.category == .document
                && $0.destination == documents
        })
        XCTAssertTrue(patterns.contains {
            $0.sourceAppBundleIdentifier == "com.apple.Safari"
                && $0.category == .image
                && $0.destination == desktop
        })
        XCTAssertTrue(patterns.contains {
            $0.sourceAppBundleIdentifier == "com.apple.mail"
                && $0.category == .document
                && $0.destination == desktop
        })
    }

    /// Accepting Perch's own suggestion must not be evidence for the pattern that
    /// produced it, or confidence would climb on Perch's output instead of the user's
    /// behavior.
    func testAcceptedSuggestionsDoNotEstablishPatterns() {
        let accepted = (0..<3).map { _ in
            route(destination: documents, origin: .acceptedSuggestion)
        }
        XCTAssertEqual(RoutePatternDetector().detectPatterns(in: accepted), [])

        let twoRealDrags = (0..<2).map { _ in route(destination: documents) }
        XCTAssertEqual(
            RoutePatternDetector().detectPatterns(in: accepted + twoRealDrags),
            []
        )
    }

    /// A confident pattern must not have its share diluted by the filings it caused.
    func testAcceptedSuggestionsDoNotDiluteAnEstablishedPattern() {
        let manual = (0..<3).map { _ in route(destination: documents) }
        let filed = (0..<9).map { _ in
            route(destination: desktop, origin: .acceptedSuggestion)
        }

        let patterns = RoutePatternDetector().detectPatterns(in: manual + filed)

        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns[0].destination, documents)
        XCTAssertEqual(patterns[0].destinationShare, 1)
    }

    private let documents = RouteDestination.folder(path: "/Users/test/Documents")
    private let desktop = RouteDestination.folder(path: "/Users/test/Desktop")

    private func route(
        sessionID: UUID = UUID(),
        sourceBundleIdentifier: String = "com.apple.Safari",
        sourceName: String = "Safari",
        category: FileCategory = .document,
        destination: RouteDestination? = nil,
        origin: RouteEventOrigin = .manualDrag
    ) -> ItemRouteEvent {
        ItemRouteEvent(
            routeSessionID: sessionID,
            shelfItemID: UUID(),
            successfulDropAtMilliseconds: 1_700_000_000_000,
            dwellTimeMilliseconds: 5_000,
            destination: destination ?? documents,
            captureMethod: origin == .acceptedSuggestion ? .perchFiling : .filePromiseWrite,
            transferMode: .move,
            sourceAppBundleIdentifier: sourceBundleIdentifier,
            sourceAppName: sourceName,
            category: category,
            origin: origin
        )
    }
}
