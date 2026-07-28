import XCTest
@testable import Perch

final class SmartPerchNamePreferenceTests: XCTestCase {
    func testEnablingDoesNotClaimNamesThatWereAlreadyOn() {
        let defaults = makeDefaults()

        let showsNames = SmartPerchNamePreference.settingAfterSmartPerchChange(
            enabled: true,
            currentlyShowsNames: true,
            defaults: defaults
        )

        XCTAssertTrue(showsNames)
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

    func testNamesAutomaticallyEnabledBySmartPerchReturnToOff() {
        let defaults = makeDefaults()
        let enabledNames = SmartPerchNamePreference.settingAfterSmartPerchChange(
            enabled: true,
            currentlyShowsNames: false,
            defaults: defaults
        )

        let disabledNames = SmartPerchNamePreference.settingAfterSmartPerchChange(
            enabled: false,
            currentlyShowsNames: enabledNames,
            defaults: defaults
        )

        XCTAssertFalse(disabledNames)
        XCTAssertNil(defaults.object(forKey: PerchSettings.smartPerchAutoEnabledNames))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SmartPerchNamePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
