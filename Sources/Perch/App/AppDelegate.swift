import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ShelfController?
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Resolved first, before anything below constructs a store that writes defaults
        // of its own: an upgrade is recognized by the preferences it already had, so the
        // question has to be asked while that evidence is still untouched.
        let firstRun = FirstRunExperience.decide()

        SmartPerchDataRemoval.completeIfPending()
        LegacySmartPerchMigration.run()
        do {
            let controller = try ShelfController()
            self.controller = controller
            controller.start()
            begin(firstRun, with: controller)
            // Start Sparkle's background update checks.
            Updater.shared.start()
        } catch {
            NSLog("Perch failed to start: \(error)")
            NSApp.terminate(nil)
        }
    }

    /// Perch used to register its own login item on first launch without asking, which
    /// made the first thing a new user saw a system notice that Perch "added items that
    /// can run in the background". The default is still on — an accessory app with no
    /// Dock tile is genuinely hard to find again once it stops coming back — but it is
    /// now a checkbox in the welcome window instead of a decision made on the user's
    /// behalf.
    @MainActor
    private func begin(_ decision: FirstRunExperience.Decision, with controller: ShelfController) {
        switch decision {
        case .none:
            break

        case .adoptExistingInstall:
            // Installed before the welcome window existed. Leave it exactly as it was,
            // login item included: `enableByDefaultIfNeeded` is a no-op for any install
            // whose first launch already applied the old default.
            LoginItemController().enableByDefaultIfNeeded()
            FirstRunExperience.markCompleted()

        case .welcome:
            let loginItem = LoginItemController()
            let welcome = WelcomeWindowController(
                loginItemAvailable: loginItem.isAvailable,
                offeredEdges: FirstRunExperience.offerableEdges()
            )
            self.welcome = welcome
            welcome.onFinish = { [weak self, weak controller] launchAtLogin, edges in
                if loginItem.isAvailable {
                    loginItem.setEnabled(launchAtLogin)
                }
                FirstRunExperience.markCompleted()
                controller?.completeFirstRun(enabling: edges)
                // Released on the next pass, not from inside its own callback: dropping
                // the last reference to the window controller here would deallocate the
                // very closure that is still running.
                DispatchQueue.main.async { self?.welcome = nil }
            }
            welcome.show()
        }
    }

    // Perch has no Dock icon, so double-clicking the app in Finder is the user's
    // natural "where did it go?" gesture — use it to rescue a stranded shelf and
    // bring it back into view.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.handleReopen()
        return false
    }
}
