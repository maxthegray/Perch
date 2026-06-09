import AppKit
import SwiftUI

/// Owns the (lazily created) History window. Perch is an accessory app, so showing the
/// window also activates the app so it can come forward and accept focus.
@MainActor
final class HistoryWindowController {
    private let ledger: ProvenanceLedger
    private var window: NSWindow?

    init(ledger: ProvenanceLedger) {
        self.ledger = ledger
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: HistoryView(ledger: ledger))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Perch History"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 420, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
