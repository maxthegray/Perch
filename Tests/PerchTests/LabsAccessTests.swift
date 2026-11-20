import XCTest
@testable import Perch

final class LabsAccessTests: XCTestCase {
    func testLockTurnsEveryFeatureOffAndHidesLabs() {
        let defaults = UserDefaults.standard
        let keys = LabsAccess.featureKeys + [PerchSettings.labsUnlocked]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.set(true, forKey: key) }

        LabsAccess.lock()

        XCTAssertFalse(LabsAccess.isUnlocked)
        for key in LabsAccess.featureKeys {
            XCTAssertFalse(defaults.bool(forKey: key), key)
        }
    }
}
