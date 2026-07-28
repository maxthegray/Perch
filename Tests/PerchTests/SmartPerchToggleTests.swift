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

    // MARK: - The master switch

    /// The point of the split: with the master switch off nothing is constructed, so
    /// there is no event log to write to and no OCR worker to run. A feature that
    /// returned a live object here would be back to hiding its output while recording.
    func testFeatureIsNotBuiltAtAllWhileTheMasterSwitchIsOff() {
        withSmartPerch(enabled: false) {
            let databaseURL = temporaryDatabaseURL()
            XCTAssertNil(makeFeature(databaseURL: databaseURL))
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: databaseURL.path),
                "off has to mean no event log is created at all"
            )
        }
    }

    func testFeatureIsBuiltWhenTheMasterSwitchIsOn() {
        withSmartPerch(enabled: true) {
            let databaseURL = temporaryDatabaseURL()
            XCTAssertNotNil(makeFeature(databaseURL: databaseURL))
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: databaseURL.path),
                "the event log is created only once the feature exists"
            )
        }
    }

    /// An unwritable log must not take the shelf down with it — the caller treats a
    /// failed open exactly like the switch being off.
    func testFeatureFailsSoftlyWhenTheEventLogCannotBeOpened() {
        withSmartPerch(enabled: true) {
            let unopenable = URL(fileURLWithPath: "/dev/null/perch-smart.sqlite")
            XCTAssertNil(makeFeature(databaseURL: unopenable))
        }
    }

    /// "Show suggestions" is the *other* switch: learning keeps running, the shelf just
    /// stops displaying it. This is what the single old toggle did silently.
    func testShowSuggestionsDefaultsOnSoTurningSmartPerchOnShowsItsWork() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: PerchSettings.smartPerchShowsSuggestions)
        defaults.removeObject(forKey: PerchSettings.smartPerchShowsSuggestions)
        defer { defaults.set(previous, forKey: PerchSettings.smartPerchShowsSuggestions) }

        XCTAssertTrue(SmartPerchSettings.showsSuggestions)
    }

    /// Ships off: a shelf is a shelf until the user asks for more.
    func testSmartPerchDefaultsOffForAnInstallThatHasNeverTouchedIt() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: PerchSettings.smartPerchEnabled)
        defaults.removeObject(forKey: PerchSettings.smartPerchEnabled)
        defer { defaults.set(previous, forKey: PerchSettings.smartPerchEnabled) }

        XCTAssertFalse(SmartPerchSettings.isEnabled)
    }

    // MARK: - Helpers

    private func makeFeature(databaseURL: URL) -> SmartPerchFeature? {
        SmartPerchFeature(
            databaseURL: databaseURL,
            smartNames: SmartNameStore(),
            routeSuggestions: RouteSuggestionStore(),
            arrivals: RecentArrivals(),
            currentItems: { [] }
        )
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchToggleTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("smart-perch.sqlite", isDirectory: false)
    }

    private func withSmartPerch(enabled: Bool, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: PerchSettings.smartPerchEnabled)
        defaults.set(enabled, forKey: PerchSettings.smartPerchEnabled)
        defer {
            if let previous {
                defaults.set(previous, forKey: PerchSettings.smartPerchEnabled)
            } else {
                defaults.removeObject(forKey: PerchSettings.smartPerchEnabled)
            }
        }
        body()
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
