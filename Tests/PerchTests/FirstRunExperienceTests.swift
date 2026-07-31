import Foundation
import XCTest
@testable import Perch

final class FirstRunExperienceTests: XCTestCase {
    func testAFreshInstallIsGreeted() {
        XCTAssertEqual(
            FirstRunExperience.decide(hasCompletedFirstRun: false, hasUsageMarkers: false),
            .welcome
        )
    }

    func testAnInstallThatPredatesTheWelcomeWindowIsAdoptedSilently() {
        // The upgrade case: 0.9 wrote preferences but never a first-run flag. Greeting it
        // would re-ask a question it has already effectively answered — and answering
        // "no" would unregister a login item the user never complained about.
        XCTAssertEqual(
            FirstRunExperience.decide(hasCompletedFirstRun: false, hasUsageMarkers: true),
            .adoptExistingInstall
        )
    }

    func testFirstRunHappensOnlyOnce() {
        XCTAssertEqual(
            FirstRunExperience.decide(hasCompletedFirstRun: true, hasUsageMarkers: false),
            .none
        )
        XCTAssertEqual(
            FirstRunExperience.decide(hasCompletedFirstRun: true, hasUsageMarkers: true),
            .none
        )
    }

    // MARK: - Reading the decision off disk

    func testAnEmptyDefaultsDomainReadsAsAFreshInstall() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(FirstRunExperience.decide(defaults: defaults), .welcome)
    }

    func testAnyOneUsageMarkerIsEnoughToRecognizeAnUpgrade() {
        for marker in FirstRunExperience.usageMarkers {
            let defaults = isolatedDefaults()
            defaults.set("something", forKey: marker)
            XCTAssertEqual(
                FirstRunExperience.decide(defaults: defaults),
                .adoptExistingInstall,
                "\(marker) should identify an install that was already in use"
            )
        }
    }

    func testTheSizePresetMigrationIsNotMistakenForPriorUse() {
        // ThemeStore.init writes `sizePreset` on every install's first launch. If it
        // counted as evidence of prior use, no one would ever see the welcome window.
        let defaults = isolatedDefaults()
        defaults.set("standard", forKey: PerchSettings.sizePreset)
        XCTAssertEqual(FirstRunExperience.decide(defaults: defaults), .welcome)
    }

    func testMarkingCompletedSticks() {
        let defaults = isolatedDefaults()
        FirstRunExperience.markCompleted(defaults: defaults)
        XCTAssertEqual(FirstRunExperience.decide(defaults: defaults), .none)
    }

    // MARK: - Where the shelf ends up

    @MainActor
    func testTheShelfComesOutOnTheLeftWheneverTheLeftEdgeWasChosen() {
        XCTAssertEqual(ShelfController.homeEdge(among: [.left, .right]), .left)
        XCTAssertEqual(ShelfController.homeEdge(among: [.left, .right, .notch]), .left)
        XCTAssertEqual(ShelfController.homeEdge(among: [.left]), .left)
    }

    @MainActor
    func testTurningTheLeftEdgeOffMovesTheShelfToAnEdgeThatExists() {
        // Without this the first reveal would fall back to whichever dock is nearest the
        // pointer, seating the shelf wherever the welcome window happened to leave it.
        XCTAssertEqual(ShelfController.homeEdge(among: [.right, .notch]), .right)
        XCTAssertEqual(ShelfController.homeEdge(among: [.notch]), .notch)
    }

    /// A private defaults domain per test, so these never read or disturb the real
    /// Perch preferences on the machine running them.
    private func isolatedDefaults(
        function: String = #function
    ) -> UserDefaults {
        let suite = "PerchTests.FirstRun.\(function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("could not create an isolated defaults domain")
        }
        // Only the suite name crosses into the teardown block; sending the instance
        // itself would be a data race the compiler rightly rejects.
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
