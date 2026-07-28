import XCTest
@testable import Perch

final class UpdateTrackStoreTests: XCTestCase {
    func testStandardBuildUsesItsBundledFeedUntilUserOptsIn() {
        let defaults = makeDefaults()
        let store = UpdateTrackStore(defaults: defaults, bundledTrack: .standard)

        XCTAssertEqual(store.selectedTrack, .standard)
        XCTAssertNil(store.feedURLString)
    }

    func testSmartBuildUsesSmartFeedWithoutAStoredSelection() {
        let defaults = makeDefaults()
        let store = UpdateTrackStore(defaults: defaults, bundledTrack: .smart)

        XCTAssertEqual(store.selectedTrack, .smart)
        XCTAssertEqual(store.feedURLString, UpdateTrackStore.smartFeedURL)
    }

    func testEnrollmentPersistsTrackAndPendingActivation() {
        let defaults = makeDefaults()
        let store = UpdateTrackStore(defaults: defaults, bundledTrack: .standard)

        store.enrollInSmartPerch()

        XCTAssertEqual(store.selectedTrack, .smart)
        XCTAssertTrue(defaults.bool(forKey: UpdateTrackStore.smartEnrollmentPendingKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "UpdateTrackStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
