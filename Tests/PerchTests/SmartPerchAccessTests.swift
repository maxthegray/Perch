import Foundation
import XCTest
@testable import Perch

final class SmartPerchAccessTests: XCTestCase {
    private var savedUnlocked: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedUnlocked = defaults.object(forKey: PerchSettings.smartPerchUnlocked)
        defaults.removeObject(forKey: PerchSettings.smartPerchUnlocked)
    }

    override func tearDown() {
        restore(savedUnlocked, forKey: PerchSettings.smartPerchUnlocked)
        super.tearDown()
    }

    func testSmartPerchIsLockedOnAFreshInstall() {
        XCTAssertFalse(SmartPerchAccess.isUnlocked)
    }

    func testUnlockingPersists() {
        SmartPerchAccess.unlock()
        XCTAssertTrue(SmartPerchAccess.isUnlocked)
    }

    func testLockingHidesThePane() {
        SmartPerchAccess.unlock()
        SmartPerchAccess.lock()
        XCTAssertFalse(SmartPerchAccess.isUnlocked)
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
