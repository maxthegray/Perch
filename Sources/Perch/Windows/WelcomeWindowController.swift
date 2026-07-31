import AppKit
import SwiftUI

/// The answers the welcome window collects. Owned by the controller so that dismissing
/// the window by any route commits the same choice — see `WelcomeView.choices`.
@MainActor
final class WelcomeChoices: ObservableObject {
    @Published var launchAtLogin = true
    /// Starts on Perch's shipping default (both side docks). The notch is opt-in and is
    /// only offered at all on a display that has one.
    @Published var edges: Set<ShelfEdge> = [.left, .right]
}

/// Owns the welcome window shown once, on a new install.
///
/// Perch is an accessory app, so — exactly as in `SettingsWindowController` — showing a
/// window also has to activate the app before it can come forward and take focus.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    /// Fires once with the collected answers, whether the user pressed the button or
    /// closed the window. Never fires twice.
    var onFinish: ((_ launchAtLogin: Bool, _ edges: Set<ShelfEdge>) -> Void)?

    private let choices = WelcomeChoices()
    private let loginItemAvailable: Bool
    private let offeredEdges: [ShelfEdge]
    private var window: NSWindow?
    private var hasFinished = false

    init(loginItemAvailable: Bool, offeredEdges: [ShelfEdge]) {
        self.loginItemAvailable = loginItemAvailable
        self.offeredEdges = offeredEdges
    }

    func show() {
        guard window == nil else {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: WelcomeView(
                choices: choices,
                loginItemAvailable: loginItemAvailable,
                offeredEdges: offeredEdges,
                onFinish: { [weak self] in self?.finish() }
            )
        )
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        // A welcome card, not a document: keep the close button but drop the chrome the
        // title bar would otherwise draw across the top of the content.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to \(PerchProductIdentity.displayName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Commit the answers and close. Idempotent: `windowWillClose` routes through here
    /// too, so the button's own `close()` must not fire the callback a second time.
    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinish?(loginItemAvailable && choices.launchAtLogin, choices.edges)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }
}
