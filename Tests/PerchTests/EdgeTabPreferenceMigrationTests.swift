import Foundation
import XCTest
@testable import Perch

final class EdgeTabPreferenceMigrationTests: XCTestCase {
    func testMigrationTurnsTheEdgeReminderOnOnce() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: PerchSettings.edgeTabOffByDefaultMigrationCompleted)
        defaults.set(false, forKey: PerchSettings.showsEdgeTab)

        EdgeTabPreferenceMigration.run(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsEdgeTab))
        XCTAssertTrue(defaults.bool(
            forKey: PerchSettings.edgeReminderOnByDefaultMigrationCompleted
        ))
    }

    func testAFreshInstallEndsWithTheReminderOn() {
        let defaults = isolatedDefaults()

        EdgeTabPreferenceMigration.run(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsEdgeTab))
    }

    func testMigrationRunsOnlyOnceSoLaterUserChoiceIsPreserved() {
        let defaults = isolatedDefaults()
        EdgeTabPreferenceMigration.run(defaults: defaults)
        defaults.set(false, forKey: PerchSettings.showsEdgeTab)

        EdgeTabPreferenceMigration.run(defaults: defaults)

        XCTAssertFalse(defaults.bool(forKey: PerchSettings.showsEdgeTab))
    }

    private func isolatedDefaults(
        function: String = #function
    ) -> UserDefaults {
        let suite = "PerchTests.EdgeTabMigration.\(function).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("could not create an isolated defaults domain")
        }
        addTeardownBlock {
            UserDefaults().removePersistentDomain(forName: suite)
        }
        return defaults
    }
}
