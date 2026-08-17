import Foundation
import SmartPerchCore
import XCTest
@testable import Perch

@MainActor
final class SmartNamePresentationTests: XCTestCase {
    func testAdoptedGhostKeepsItsGeneratedNameUntilSuggestionIsPersisted() {
        let store = SmartNameStore()
        let itemID = UUID()

        store.registerScreenshot(itemID)
        store.setProvisionalName("Messages — Lachlan Wession", for: itemID)

        XCTAssertEqual(
            store.presentation(
                for: itemID,
                originalTitle: "Screenshot 2026-07-27 at 1.23.45 AM.png"
            ),
            SmartNameStore.NamePresentation(
                title: "Messages — Lachlan Wession",
                isAnalyzing: false
            )
        )

        let suggestion = AvailableFilenameSuggestion(
            fileID: UUID(),
            shelfItemID: itemID,
            originalFilename: "Screenshot 2026-07-27 at 1.23.45 AM.png",
            displayName: "Messages — Lachlan Wession",
            suggestedFilename: "Messages — Lachlan Wession.png"
        )
        store.set(suggestion)

        XCTAssertEqual(store.suggestion(for: itemID), suggestion)
        XCTAssertNil(store.provisionalNamesByItemID[itemID])
    }

    func testScreenshotUsesStablePlaceholderThenHugsGeneratedName() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.beginAnalyzingScreenshot(itemID)

        XCTAssertEqual(
            store.presentation(
                for: itemID,
                originalTitle: "Screenshot 2026-07-27 at 1.23.45 AM.png"
            ),
            SmartNameStore.NamePresentation(
                title: "Screenshot",
                isAnalyzing: true
            )
        )

        store.set(
            AvailableFilenameSuggestion(
                fileID: UUID(),
                shelfItemID: itemID,
                originalFilename: "Screenshot 2026-07-27 at 1.23.45 AM.png",
                displayName: "Terminal — Perch",
                suggestedFilename: "terminal-perch.png"
            )
        )
        store.finishAnalyzingScreenshot(itemID)

        XCTAssertEqual(
            store.presentation(for: itemID, originalTitle: "Ignored.png"),
            SmartNameStore.NamePresentation(
                title: "Terminal — Perch",
                isAnalyzing: false
            )
        )
    }

    func testScreenshotWithoutSuggestionKeepsQuietFallback() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.beginAnalyzingScreenshot(itemID)
        store.finishAnalyzingScreenshot(itemID)

        XCTAssertEqual(
            store.presentation(
                for: itemID,
                originalTitle: "Screenshot 2026-07-27 at 1.23.45 AM.png"
            ).title,
            "Screenshot"
        )
    }

    func testPDFKeepsItsFilenameWhileShowingAnalysis() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.beginAnalyzing(itemID)

        XCTAssertEqual(
            store.presentation(for: itemID, originalTitle: "Scanned document.pdf"),
            SmartNameStore.NamePresentation(
                title: "Scanned document.pdf",
                isAnalyzing: true
            )
        )
    }

    func testDismissRestoresOriginalFilenamePresentation() {
        let store = SmartNameStore()
        let itemID = UUID()
        store.registerScreenshot(itemID)
        store.set(
            AvailableFilenameSuggestion(
                fileID: UUID(),
                shelfItemID: itemID,
                originalFilename: "Screenshot.png",
                displayName: "Messages — Alex",
                suggestedFilename: "messages-alex.png"
            )
        )

        store.remove(for: itemID)

        XCTAssertEqual(
            store.presentation(
                for: itemID,
                originalTitle: "Screenshot.png"
            ),
            SmartNameStore.NamePresentation(
                title: "Screenshot.png",
                isAnalyzing: false
            )
        )
    }

    func testScreenshotFilenameRecognitionIsConservative() {
        XCTAssertTrue(
            ScreenshotNamePresentation.filenameLooksLikeScreenshot(
                "Screen Shot 2026-07-27 at 1.23.45 AM.png"
            )
        )
        XCTAssertTrue(
            ScreenshotNamePresentation.filenameLooksLikeScreenshot(
                "screenshot.png"
            )
        )
        XCTAssertFalse(
            ScreenshotNamePresentation.filenameLooksLikeScreenshot(
                "vacation-photo.png"
            )
        )
    }
}
