import XCTest
@testable import Perch

final class SmartPerchEnrollmentTests: XCTestCase {
    func testPendingEnrollmentActivatesSmartPerchAndLabs() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UpdateTrackStore.smartEnrollmentPendingKey)
        defaults.set(false, forKey: PerchSettings.showsLabels)

        SmartPerchEnrollment.completeIfPending(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchEnabled))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsLabels))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.smartPerchAutoEnabledNames))
        XCTAssertTrue(defaults.bool(forKey: PerchSettings.labsUnlocked))
        XCTAssertNil(defaults.object(forKey: UpdateTrackStore.smartEnrollmentPendingKey))
    }

    func testPendingEnrollmentDoesNotClaimNamesThatWereAlreadyOn() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: UpdateTrackStore.smartEnrollmentPendingKey)
        defaults.set(true, forKey: PerchSettings.showsLabels)

        SmartPerchEnrollment.completeIfPending(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: PerchSettings.showsLabels))
        XCTAssertNil(defaults.object(forKey: PerchSettings.smartPerchAutoEnabledNames))
    }

    func testManualNameChoiceSurvivesDisablingSmartPerch() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: PerchSettings.smartPerchAutoEnabledNames)

        SmartPerchNamePreference.userChangedNames(defaults: defaults)
        let showsNames = SmartPerchNamePreference.settingAfterSmartPerchChange(
            enabled: false,
            currentlyShowsNames: true,
            defaults: defaults
        )

        XCTAssertTrue(showsNames)
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
