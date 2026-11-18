import AppKit
import XCTest
@testable import Perch

/// Triple-click (a Labs feature) puts the shelf away from anywhere on the card,
/// including the inert background of an empty shelf, which the host view declines and
/// the drop view beneath it receives.
@MainActor
final class ShelfTripleClickTests: XCTestCase {
    private var savedDefaults: [String: Any?] = [:]
    private let keys = [PerchSettings.labsUnlocked, PerchSettings.tripleClickToHide]

    override func setUp() {
        super.setUp()
        savedDefaults = Dictionary(uniqueKeysWithValues: keys.map {
            ($0, UserDefaults.standard.object(forKey: $0))
        })
    }

    override func tearDown() {
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    func testTripleClickOnAnEmptyShelfPutsItAway() {
        UserDefaults.standard.set(true, forKey: PerchSettings.labsUnlocked)
        UserDefaults.standard.set(true, forKey: PerchSettings.tripleClickToHide)
        XCTAssertEqual(tripleClicks(), 1)
    }

    func testTripleClickDoesNothingWhileOff() {
        UserDefaults.standard.set(true, forKey: PerchSettings.labsUnlocked)
        UserDefaults.standard.removeObject(forKey: PerchSettings.tripleClickToHide)
        XCTAssertEqual(tripleClicks(), 0)
    }

    func testTripleClickDoesNothingWhileLabsIsLocked() {
        UserDefaults.standard.set(false, forKey: PerchSettings.labsUnlocked)
        UserDefaults.standard.set(true, forKey: PerchSettings.tripleClickToHide)
        XCTAssertEqual(tripleClicks(), 0)
    }

    /// Clicks once, twice, then three times, and counts put-away requests.
    private func tripleClicks() -> Int {
        let holding = HoldingDirectory(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShelfTripleClickTests-\(UUID().uuidString)", isDirectory: true)
        )
        let hostView = ShelfHostView(
            store: ItemStore(holding: holding),
            themeStore: ThemeStore(),
            ledger: ProvenanceLedger(holding: holding),
            arrivals: RecentArrivals(),
            smartNames: SmartNameStore(),
            routeSuggestions: RouteSuggestionStore()
        )
        var tripleClicks = 0
        hostView.onTripleClick = { tripleClicks += 1 }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.close() }
        let dropView = ShelfDropView(frame: panel.contentView!.bounds)
        dropView.addSubview(hostView)
        hostView.frame = dropView.bounds
        dropView.onUnclaimedPress = { event in hostView.unclaimedPressBegan(event) }
        panel.contentView = dropView
        // Mouse events only route to a window that is ordered in; far off-screen so
        // nothing appears on the display running the tests.
        panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()

        func press(clickCount: Int) {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type,
                    location: NSPoint(x: 120, y: 80),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: clickCount,
                    pressure: 1
                )!
                panel.sendEvent(event)
            }
        }

        press(clickCount: 1)
        press(clickCount: 2)
        XCTAssertEqual(tripleClicks, 0)
        press(clickCount: 3)
        return tripleClicks
    }
}
