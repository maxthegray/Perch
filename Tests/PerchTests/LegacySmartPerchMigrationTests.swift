import XCTest
@testable import Perch

final class LegacySmartPerchMigrationTests: XCTestCase {
    func testFreshInstallStaysRegularAndLocked() {
        let defaults = makeDefaults()

        LegacySmartPerchMigration.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertNil(defaults.object(forKey: PerchSettings.labsUnlocked))
    }

    func testPendingEnrollmentEnablesSmartPerchAndNames() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: LegacySmartPerchMigration.enrollmentPendingKey)
        defaults.set(false, forKey: PerchSettings.showsLabels)

        LegacySmartPerchMigration.run(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.labsUnlocked))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsLabels))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchAutoEnabledNames))
    }

    func testExistingEnabledSmartPerchStaysEnabledAndReachable() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: PerchSettings.smartPerchEnabled)

        LegacySmartPerchMigration.run(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.labsUnlocked))
    }

    func testObsoleteTrackKeysAreRemovedWithoutEnablingSmartPerch() {
        let defaults = makeDefaults()
        defaults.set("smart", forKey: LegacySmartPerchMigration.selectionKey)

        LegacySmartPerchMigration.run(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: LegacySmartPerchMigration.selectionKey))
        XCTAssertNil(defaults.object(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertNil(defaults.object(forKey: PerchSettings.labsUnlocked))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LegacySmartPerchMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
