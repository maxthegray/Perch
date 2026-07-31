import AppKit
import SwiftUI

/// The answers the welcome window collects. Owned by the controller so that dismissing
/// the window by any route commits the same choice — see `WelcomeView.choices`.
@MainActor
final class WelcomeChoices: ObservableObject {
    @Published var launchAtLogin: Bool
    @Published var edges: Set<ShelfEdge>

    /// A new install starts on Perch's shipping defaults: both side docks (the notch is
    /// opt-in, and only offered at all on a display that has one) and Launch at Login on.
    ///
    /// A *returning* user must be seeded with what they already have instead. This window
    /// commits its answers on any dismissal, so defaults here would mean closing it turned
    /// Launch at Login back on for someone who had switched it off, and replaced their
    /// edge selection with Perch's — settings changed by a window they only glanced at.
    init(launchAtLogin: Bool = true, edges: Set<ShelfEdge> = [.left, .right]) {
        self.launchAtLogin = launchAtLogin
        self.edges = edges
    }
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

    private let choices: WelcomeChoices
    private let loginItemAvailable: Bool
    private let offeredEdges: [ShelfEdge]
    private let mode: WelcomeMode
    private var window: NSWindow?
    private var hasFinished = false

    init(
        loginItemAvailable: Bool,
        offeredEdges: [ShelfEdge],
        mode: WelcomeMode = .firstRun,
        choices: WelcomeChoices? = nil
    ) {
        self.loginItemAvailable = loginItemAvailable
        self.offeredEdges = offeredEdges
        self.mode = mode
        // Built here rather than as a default argument: default arguments are
        // evaluated in the caller's context, which is not the main actor.
        self.choices = choices ?? WelcomeChoices()
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
                mode: mode,
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
        window.title = mode.windowTitle
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
