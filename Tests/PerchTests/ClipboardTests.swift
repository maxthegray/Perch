import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Perch

final class KeyComboTests: XCTestCase {
    func testDefaultIsOptionCommandC() {
        XCTAssertEqual(KeyCombo.clipboardDefault.displayString, "⌥⌘C")
        XCTAssertEqual(KeyCombo.clipboardDefault.carbonModifiers, UInt32(cmdKey | optionKey))
    }

    func testNeedsCommandControlOrOption() {
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [], key: "v"))
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.shift], key: "v"))
        XCTAssertNotNil(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control], key: "v"))
        XCTAssertNotNil(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option], key: "v"))
    }

    func testModifierKeysAloneAreNotShortcuts() {
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_Command), modifiers: [.command], key: ""))
    }

    func testDisplayOrderAndSpecialKeys() {
        let combo = KeyCombo(
            keyCode: UInt32(kVK_Space), modifiers: [.command, .option, .control, .shift], key: " "
        )
        XCTAssertEqual(combo?.displayString, "⌃⌥⇧⌘Space")
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option, .command], key: "v")?
            .displayString, "⌥⌘V")
    }

    func testIgnoresNonShortcutModifierBits() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.command, .capsLock, .numericPad], key: "v")
        XCTAssertEqual(combo?.modifierFlags, [.command])
    }

    func testSavesAndLoads() throws {
        let suite = "KeyComboTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(KeyCombo.load(from: defaults), .clipboardDefault)
        let combo = try XCTUnwrap(KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.option, .command], key: "v"))
        combo.save(to: defaults)
        XCTAssertEqual(KeyCombo.load(from: defaults), combo)
    }
}

final class ClipboardPanelPlacementTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = NSSize(width: 380, height: 420)

    func testOpensBelowRightOfThePointer() {
        let frame = ClipboardPanelPlacement.frame(size: size, cursor: NSPoint(x: 100, y: 700), visibleFrame: screen)
        XCTAssertEqual(frame.origin, NSPoint(x: 104, y: 276))
    }

    func testFlipsLeftNearTheRightEdge() {
        let frame = ClipboardPanelPlacement.frame(size: size, cursor: NSPoint(x: 900, y: 700), visibleFrame: screen)
        XCTAssertEqual(frame.maxX, 896)
    }

    func testFlipsUpNearTheBottom() {
        let frame = ClipboardPanelPlacement.frame(size: size, cursor: NSPoint(x: 100, y: 50), visibleFrame: screen)
        XCTAssertEqual(frame.minY, 54)
    }

    func testAlwaysStaysOnScreen() {
        let offset = NSRect(x: 1000, y: -200, width: 600, height: 500)
        for cursor in [NSPoint(x: 1000, y: -200), NSPoint(x: 1600, y: 300), NSPoint(x: 1300, y: 50)] {
            let frame = ClipboardPanelPlacement.frame(size: size, cursor: cursor, visibleFrame: offset)
            XCTAssertTrue(offset.contains(frame), "\(cursor) → \(frame)")
        }
    }
}

@MainActor
final class ClipboardCoordinatorTests: XCTestCase {
    func testOnByDefault() throws {
        let saved = UserDefaults.standard.object(forKey: PerchSettings.clipboardEnabled)
        UserDefaults.standard.removeObject(forKey: PerchSettings.clipboardEnabled)
        defer { UserDefaults.standard.set(saved, forKey: PerchSettings.clipboardEnabled) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardCoordinatorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(name: .init("PerchTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let coordinator = ClipboardCoordinator(
            databaseURL: directory.appendingPathComponent("clipboard.sqlite"), pasteboard: pasteboard
        )
        coordinator.bootstrap()

        XCTAssertTrue(coordinator.isEnabled)
        coordinator.setEnabled(false)
    }

    func testSwitchedOffBuildsNothing() throws {
        let saved = UserDefaults.standard.object(forKey: PerchSettings.clipboardEnabled)
        UserDefaults.standard.set(false, forKey: PerchSettings.clipboardEnabled)
        defer { UserDefaults.standard.set(saved, forKey: PerchSettings.clipboardEnabled) }
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardCoordinatorTests-\(UUID().uuidString)")
            .appendingPathComponent("clipboard.sqlite")

        let coordinator = ClipboardCoordinator(databaseURL: databaseURL)
        coordinator.bootstrap()

        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testSwitchingOnOpensHistoryAndOffReleasesEverything() throws {
        let saved = UserDefaults.standard.object(forKey: PerchSettings.clipboardEnabled)
        defer { UserDefaults.standard.set(saved, forKey: PerchSettings.clipboardEnabled) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardCoordinatorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        let pasteboard = NSPasteboard(name: .init("PerchTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let coordinator = ClipboardCoordinator(databaseURL: databaseURL, pasteboard: pasteboard)
        coordinator.setEnabled(true)

        XCTAssertTrue(coordinator.isEnabled)
        XCTAssertTrue(ClipboardCoordinator.isSwitchedOn)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))

        coordinator.setEnabled(false)

        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertFalse(ClipboardCoordinator.isSwitchedOn)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path), "off keeps history until cleared")
        XCTAssertNil(coordinator.errorMessage)
    }

    func testClearingWhileOffDeletesTheSavedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardCoordinatorTests-\(UUID().uuidString)")
        let databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: databaseURL.path, contents: Data("old".utf8))

        let coordinator = ClipboardCoordinator(databaseURL: databaseURL)
        coordinator.clearHistory()

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertNil(coordinator.errorMessage)
    }
}

final class MagpieStyleTests: XCTestCase {
    func testDefaultsToTheMaccyLikeClassicLook() {
        let saved = UserDefaults.standard.object(forKey: PerchSettings.clipboardStyle)
        defer { UserDefaults.standard.set(saved, forKey: PerchSettings.clipboardStyle) }
        UserDefaults.standard.removeObject(forKey: PerchSettings.clipboardStyle)

        XCTAssertEqual(MagpieStyle.current, .classic)
        UserDefaults.standard.set("detailed", forKey: PerchSettings.clipboardStyle)
        XCTAssertEqual(MagpieStyle.current, .detailed)
        UserDefaults.standard.set("bogus", forKey: PerchSettings.clipboardStyle)
        XCTAssertEqual(MagpieStyle.current, .classic)
    }

    func testClassicHugsItsRowsUpToALimit() {
        let row = MagpieStyle.classicRowHeight
        XCTAssertEqual(MagpieStyle.classic.height(forRows: 3) - MagpieStyle.classic.height(forRows: 2), row)
        XCTAssertEqual(
            MagpieStyle.classic.height(forRows: 100),
            MagpieStyle.classic.height(forRows: MagpieStyle.classicMaxVisibleRows)
        )
        XCTAssertGreaterThan(MagpieStyle.classic.height(forRows: 0), MagpieStyle.classicSearchHeight)
    }

    func testDetailedIsAFixedCard() {
        XCTAssertEqual(MagpieStyle.detailed.height(forRows: 0), MagpieStyle.detailed.height(forRows: 50))
    }
}
