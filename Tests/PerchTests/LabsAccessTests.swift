import Foundation
import XCTest
@testable import Perch

final class LabsAccessTests: XCTestCase {
    private var savedUnlocked: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedUnlocked = defaults.object(forKey: PerchSettings.labsUnlocked)
        defaults.removeObject(forKey: PerchSettings.labsUnlocked)
    }

    override func tearDown() {
        restore(savedUnlocked, forKey: PerchSettings.labsUnlocked)
        super.tearDown()
    }

    func testLabsIsLockedOnAFreshInstall() {
        XCTAssertFalse(LabsAccess.isUnlocked)
    }

    func testUnlockingPersists() {
        LabsAccess.unlock()
        XCTAssertTrue(LabsAccess.isUnlocked)
    }


    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
