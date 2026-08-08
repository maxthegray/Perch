import XCTest
@testable import Perch

final class SettingsLayoutTests: XCTestCase {
    func testLayoutDefaultsToBeautiful() {
        let defaults = makeDefaults()
        XCTAssertEqual(SettingsLayout.load(from: defaults), .beautiful)
    }

    func testUglyLayoutPersists() {
        let defaults = makeDefaults()
        defaults.set(SettingsLayout.ugly.rawValue, forKey: PerchSettings.settingsLayout)
        XCTAssertEqual(SettingsLayout.load(from: defaults), .ugly)
    }

    func testUnknownLayoutFallsBackToBeautiful() {
        let defaults = makeDefaults()
        defaults.set("unknown", forKey: PerchSettings.settingsLayout)
        XCTAssertEqual(SettingsLayout.load(from: defaults), .beautiful)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SettingsLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
