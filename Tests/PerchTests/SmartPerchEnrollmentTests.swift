import XCTest
@testable import Perch

final class SmartPerchEnrollmentTests: XCTestCase {
    func testPendingEnrollmentActivatesSmartPerchAndLabs() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UpdateTrackStore.smartEnrollmentPendingKey)

        SmartPerchEnrollment.completeIfPending(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsLabels))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.labsUnlocked))
        XCTAssertNil(defaults.object(forKey: UpdateTrackStore.smartEnrollmentPendingKey))
    }

    func testOrdinarySmartBuildLaunchDoesNotEnableLabs() {
        let defaults = makeDefaults()

        SmartPerchEnrollment.completeIfPending(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertNil(defaults.object(forKey: PerchSettings.labsUnlocked))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SmartPerchEnrollmentTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
