import AppKit
import SwiftUI

/// Owns the gesture cheat sheet opened from the shelf's menu. Perch is an accessory app,
/// so showing the window also activates the app so it can come forward.
@MainActor
final class ShortcutsWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsView()))
        window.styleMask = [.titled, .closable]
        window.title = "Shortcuts"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
