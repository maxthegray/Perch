import AppKit
import XCTest
@testable import Perch

/// Triple-click puts the shelf away from anywhere on the card, including the inert
/// background of an empty shelf, which the host view declines and the drop view
/// beneath it receives.
@MainActor
final class ShelfTripleClickTests: XCTestCase {
    private var panel: NSPanel!
    private var hostView: ShelfHostView!
    private var tripleClicks = 0

    override func setUp() {
        super.setUp()
        let holding = HoldingDirectory(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShelfTripleClickTests-\(UUID().uuidString)", isDirectory: true)
        )
        hostView = ShelfHostView(
            store: ItemStore(holding: holding),
            themeStore: ThemeStore(),
            ledger: ProvenanceLedger(holding: holding),
            arrivals: RecentArrivals(),
            smartNames: SmartNameStore(),
            routeSuggestions: RouteSuggestionStore()
        )
        hostView.onTripleClick = { [weak self] in self?.tripleClicks += 1 }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let dropView = ShelfDropView(frame: panel.contentView!.bounds)
        dropView.addSubview(hostView)
        hostView.frame = dropView.bounds
        let host = hostView!
        dropView.onUnclaimedPress = { @MainActor event in host.unclaimedPressBegan(event) }
        panel.contentView = dropView
        panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()
    }

    override func tearDown() {
        panel.close()
        panel = nil
        hostView = nil
        super.tearDown()
    }

    private func press(clickCount: Int) {
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

    func testTripleClickOnAnEmptyShelfPutsItAway() {
        press(clickCount: 1)
        press(clickCount: 2)
        XCTAssertEqual(tripleClicks, 0)
        press(clickCount: 3)
        XCTAssertEqual(tripleClicks, 1)
    }
}
