import XCTest
@testable import Perch

@MainActor
final class SmartPerchCoordinatorTests: XCTestCase {
    func testBootstrapOffCreatesNoSmartDatabase() throws {
        try withCleanPreferences {
            let context = try makeContext()

            context.coordinator.bootstrap()

            XCTAssertFalse(context.coordinator.isEnabled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.databaseURL.path))
            XCTAssertFalse(SmartPerchAccess.isUnlocked)
        }
    }

    func testBootstrapKeepsExistingSmartPerchEnabled() throws {
        try withCleanPreferences {
            UserDefaults.standard.set(true, forKey: PerchSettings.smartPerchEnabled)
            let context = try makeContext()

            context.coordinator.bootstrap()

            XCTAssertTrue(context.coordinator.isEnabled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.databaseURL.path))
            XCTAssertTrue(SmartPerchAccess.isUnlocked)
        }
    }

    func testDisableKeepsDataAndRemoveDeletesOnlySmartData() async throws {
        try await withCleanPreferences {
            UserDefaults.standard.set(false, forKey: PerchSettings.showsLabels)
            let context = try makeContext()
            let shelfMarker = context.root
                .appendingPathComponent("items", isDirectory: true)
                .appendingPathComponent("keep-me")
            try FileManager.default.createDirectory(
                at: shelfMarker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: shelfMarker.path, contents: Data())

            context.coordinator.setEnabled(true)

            XCTAssertTrue(context.coordinator.isEnabled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.databaseURL.path))
            XCTAssertTrue(SmartPerchAccess.isUnlocked)
            XCTAssertTrue(context.themeStore.showsLabels)

            context.coordinator.setEnabled(false)

            XCTAssertFalse(context.coordinator.isEnabled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.databaseURL.path))
            XCTAssertFalse(context.themeStore.showsLabels)

            let removed = await context.coordinator.removeData()
            XCTAssertTrue(removed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: context.databaseURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: shelfMarker.path))
            XCTAssertFalse(SmartPerchAccess.isUnlocked)
            XCTAssertNil(
                UserDefaults.standard.object(forKey: SmartPerchDataRemoval.pendingKey)
            )
        }
    }

    func testActivationFailureFallsBackToRegularPerch() throws {
        try withCleanPreferences {
            UserDefaults.standard.set(false, forKey: PerchSettings.showsLabels)
            let holding = HoldingDirectory(
                root: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "SmartPerchCoordinatorTests-\(UUID().uuidString)",
                        isDirectory: true
                    )
            )
            let themeStore = ThemeStore()
            let coordinator = SmartPerchCoordinator(
                databaseURL: URL(fileURLWithPath: "/dev/null/smart-perch.sqlite"),
                arrivals: RecentArrivals(),
                store: ItemStore(holding: holding),
                themeStore: themeStore
            )

            coordinator.setEnabled(true)

            XCTAssertFalse(coordinator.isEnabled)
            XCTAssertNotNil(coordinator.errorMessage)
            XCTAssertFalse(themeStore.showsLabels)
            XCTAssertFalse(SmartPerchSettings.isEnabled)
            XCTAssertTrue(SmartPerchAccess.isUnlocked)
        }
    }

    private struct Context {
        let root: URL
        let databaseURL: URL
        let themeStore: ThemeStore
        let coordinator: SmartPerchCoordinator
    }

    private func makeContext() throws -> Context {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SmartPerchCoordinatorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let holding = HoldingDirectory(root: root)
        let themeStore = ThemeStore()
        return Context(
            root: root,
            databaseURL: holding.smartEventLogFile,
            themeStore: themeStore,
            coordinator: SmartPerchCoordinator(
                databaseURL: holding.smartEventLogFile,
                arrivals: RecentArrivals(),
                store: ItemStore(holding: holding),
                themeStore: themeStore
            )
        )
    }

    private func withCleanPreferences(_ body: () throws -> Void) throws {
        let restore = cleanPreferences()
        defer { restore() }
        try body()
    }

    private func withCleanPreferences(
        _ body: () async throws -> Void
    ) async throws {
        let restore = cleanPreferences()
        defer { restore() }
        try await body()
    }

    private func cleanPreferences() -> () -> Void {
        let defaults = UserDefaults.standard
        let keys = [
            PerchSettings.smartPerchEnabled,
            PerchSettings.smartPerchUnlocked,
            PerchSettings.smartPerchAutoEnabledNames,
            PerchSettings.showsLabels,
            PerchSettings.sizePreset,
            PerchSettings.widthScale,
            PerchSettings.heightFraction,
            SmartPerchDataRemoval.pendingKey
        ]
        let saved = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            defaults.object(forKey: key).map { (key, $0) }
        })
        keys.forEach(defaults.removeObject(forKey:))
        return {
            keys.forEach(defaults.removeObject(forKey:))
            for (key, value) in saved {
                defaults.set(value, forKey: key)
            }
        }
    }
}
