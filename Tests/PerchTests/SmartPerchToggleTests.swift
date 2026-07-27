import Foundation
import SmartPerchCore
import XCTest
@testable import Perch

@MainActor
final class SmartPerchToggleTests: XCTestCase {
    func testDisabledSmartPerchShowsTheFilenameInsteadOfAGeneratedName() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.beginAnalyzingScreenshot(itemID)
        store.set(suggestion(for: itemID))
        store.isEnabled = false

        XCTAssertEqual(
            store.presentation(
                for: itemID,
                originalTitle: "Screenshot 2026-07-27 at 1.23.45 AM.png"
            ),
            SmartNameStore.NamePresentation(
                title: "Screenshot 2026-07-27 at 1.23.45 AM.png",
                isAnalyzing: false,
                usesStableWidth: false
            )
        )
        XCTAssertNil(store.suggestion(for: itemID))
    }

    /// The generated name is kept, not discarded, so switching Smart Perch back on
    /// shows what was learned while it was off rather than re-running Vision.
    func testGeneratedNamesSurviveBeingHiddenAndReappearOnReenable() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.set(suggestion(for: itemID))

        store.isEnabled = false
        XCTAssertNil(store.suggestion(for: itemID))

        store.isEnabled = true
        XCTAssertEqual(
            store.presentation(for: itemID, originalTitle: "Ignored.png").title,
            "Terminal — Perch"
        )
    }

    func testDisabledSmartPerchWithholdsLearnedRoutesWithoutForgettingThem() {
        let store = RouteSuggestionStore()
        let itemID = UUID()
        store.replace(with: [itemID: route(for: itemID)])

        store.isEnabled = false
        XCTAssertNil(store.suggestion(for: itemID))

        store.isEnabled = true
        XCTAssertEqual(
            store.suggestion(for: itemID)?.destination,
            .folder(path: "/Users/test/Documents")
        )
    }

    /// A screenshot ghost would otherwise sit on the generic "Screenshot" label forever,
    /// because with Smart Perch off no generated name is ever going to replace it.
    func testDisabledSmartPerchNamesAScreenshotGhostByItsRealFilename() {
        let offer = ArrivalOffer(
            url: URL(fileURLWithPath: "/Users/test/Desktop/Screenshot 2026-07-27 at 1.23.45 AM.png"),
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            location: .desktop
        )
        XCTAssertTrue(offer.usesStableScreenshotName)

        let ghost = ArrivalGhost.offer(
            offer,
            session: ArrivalSession(id: UUID(), offers: [offer])
        )

        XCTAssertEqual(
            ghost.displayTitle(smartName: nil, usesScreenshotPlaceholder: false),
            "Screenshot 2026-07-27 at 1.23.45 AM.png"
        )
        XCTAssertEqual(
            ghost.displayTitle(smartName: nil),
            ScreenshotNamePresentation.placeholder
        )
    }

    private func suggestion(for itemID: UUID) -> AvailableFilenameSuggestion {
        AvailableFilenameSuggestion(
            fileID: UUID(),
            shelfItemID: itemID,
            originalFilename: "Screenshot 2026-07-27 at 1.23.45 AM.png",
            displayName: "Terminal — Perch",
            suggestedFilename: "terminal-perch.png"
        )
    }

    private func route(for itemID: UUID) -> SuggestedRoute {
        SuggestedRoute(
            shelfItemID: itemID,
            destination: .folder(path: "/Users/test/Documents"),
            occurrenceCount: 4,
            destinationShare: 1
        )
    }
}
