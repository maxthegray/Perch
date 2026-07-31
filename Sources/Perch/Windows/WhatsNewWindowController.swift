import AppKit
import SwiftUI

/// Owns the What's New window shown once after an update.
///
/// Structured exactly like `WelcomeWindowController`, including the accessory-app
/// activation dance: Perch has no Dock tile, so a window has to activate the app before
/// it can come forward and take focus.
@MainActor
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    /// Fires once, whether the user pressed Continue or closed the window. The version is
    /// stamped from here, so dismissing by any route counts as having seen it.
    var onFinish: (() -> Void)?

    private let notes: [ReleaseNote]
    private var window: NSWindow?
    private var hasFinished = false

    init(notes: [ReleaseNote]) {
        self.notes = notes
    }

    func show() {
        guard window == nil else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: WhatsNewView(
                notes: notes,
                onDismiss: { [weak self] in self?.finish() }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "What's New in \(PerchProductIdentity.displayName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Idempotent, for the same reason the welcome window's is: `windowWillClose` routes
    /// through here too, so the button's own `close()` must not fire the callback twice.
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinish?()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
