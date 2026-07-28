import Foundation
import XCTest
@testable import Perch

final class LabsAccessTests: XCTestCase {
    private var savedUnlocked: Any?
    private var savedSmartPerch: Any?

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        savedUnlocked = defaults.object(forKey: PerchSettings.labsUnlocked)
        savedSmartPerch = defaults.object(forKey: PerchSettings.smartPerchEnabled)
        defaults.removeObject(forKey: PerchSettings.labsUnlocked)
        defaults.removeObject(forKey: PerchSettings.smartPerchEnabled)
    }

    override func tearDown() {
        restore(savedUnlocked, forKey: PerchSettings.labsUnlocked)
        restore(savedSmartPerch, forKey: PerchSettings.smartPerchEnabled)
        super.tearDown()
    }

    func testLabsIsLockedOnAFreshInstall() {
        XCTAssertFalse(LabsAccess.isUnlocked)
    }

    /// The common case for an existing install: the toggle was never touched, so there is
    /// no stored value. Smart Perch now reads as off, and Labs stays hidden.
    func testAnInstallThatNeverTouchedSmartPerchStaysLocked() {
        LabsAccess.unlockIfSmartPerchWasAlreadyOn()
        XCTAssertFalse(LabsAccess.isUnlocked)
    }

    /// Someone who deliberately switched Smart Perch on keeps it — and must still be able
    /// to reach the switch, or they are left with a feature running and no way off.
    func testAnInstallWithSmartPerchExplicitlyOnIsUnlocked() {
        UserDefaults.standard.set(true, forKey: PerchSettings.smartPerchEnabled)

        LabsAccess.unlockIfSmartPerchWasAlreadyOn()

        XCTAssertTrue(LabsAccess.isUnlocked)
    }

    func testAnInstallWithSmartPerchExplicitlyOffStaysLocked() {
        UserDefaults.standard.set(false, forKey: PerchSettings.smartPerchEnabled)

        LabsAccess.unlockIfSmartPerchWasAlreadyOn()

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
