import XCTest
@testable import Perch

final class PendingUpdateTests: XCTestCase {
    func testNewerFoundVersionIsOffered() {
        XCTAssertEqual(Updater.pendingUpdate(found: "1.10.0", running: "1.9.1")?.description, "1.10.0")
    }

    func testInstalledOrOlderVersionIsNotOffered() {
        XCTAssertNil(Updater.pendingUpdate(found: "1.10.0", running: "1.10.0"))
        XCTAssertNil(Updater.pendingUpdate(found: "1.9.1", running: "1.10.0"))
    }

    func testMissingOrUnparseableVersionsOfferNothing() {
        XCTAssertNil(Updater.pendingUpdate(found: nil, running: "1.9.1"))
        XCTAssertNil(Updater.pendingUpdate(found: "1.10.0", running: "Development"))
    }
}
