import XCTest
@testable import Perch

final class SmartPerchDataRemovalTests: XCTestCase {
    func testRequestSwitchesToStandardAndRemovesSmartData() throws {
        let defaults = makeDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchDataRemovalTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("smart-perch.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for suffix in ["", "-wal", "-shm", "-journal"] {
            FileManager.default.createFile(
                atPath: databaseURL.path + suffix,
                contents: Data("smart".utf8)
            )
        }
        defaults.set(true, forKey: "Perch.SmartPerchEnabled")
        defaults.set(false, forKey: "Perch.SmartPerchShowsSuggestions")
        defaults.set(true, forKey: "Perch.LabsUnlocked")
        defaults.set(true, forKey: "Perch.ShowsLabels")
        defaults.set(true, forKey: PerchSettings.smartPerchAutoEnabledNames)

        SmartPerchDataRemoval.request(defaults: defaults, databaseURL: databaseURL)

        XCTAssertEqual(
            defaults.string(forKey: UpdateTrackStore.selectionKey),
            PerchUpdateTrack.standard.rawValue
        )
        XCTAssertFalse(defaults.bool(forKey: "Perch.SmartPerchEnabled"))
        XCTAssertNil(defaults.object(forKey: "Perch.SmartPerchShowsSuggestions"))
        XCTAssertFalse(defaults.bool(forKey: "Perch.LabsUnlocked"))
        XCTAssertFalse(defaults.bool(forKey: "Perch.ShowsLabels"))
        XCTAssertTrue(defaults.bool(forKey: SmartPerchDataRemoval.pendingKey))
        for suffix in ["", "-wal", "-shm", "-journal"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + suffix))
        }
    }

    func testRequestPreservesNamesThatSmartPerchDidNotEnable() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "Perch.ShowsLabels")
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchDataRemovalTests-\(UUID().uuidString).sqlite")

        SmartPerchDataRemoval.request(defaults: defaults, databaseURL: databaseURL)

        XCTAssertTrue(defaults.bool(forKey: "Perch.ShowsLabels"))
    }

    func testNextLaunchRepeatsRemovalAndClearsPendingFlag() throws {
        let defaults = makeDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchDataRemovalTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("smart-perch.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        defaults.set(true, forKey: SmartPerchDataRemoval.pendingKey)
        FileManager.default.createFile(
            atPath: databaseURL.path,
            contents: Data("recreated".utf8)
        )

        SmartPerchDataRemoval.completeIfPending(
            defaults: defaults,
            databaseURL: databaseURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertNil(defaults.object(forKey: SmartPerchDataRemoval.pendingKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "SmartPerchDataRemovalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
