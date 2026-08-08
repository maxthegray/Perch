import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ShelfController?
    private var welcome: WelcomeWindowController?
    private var whatsNew: WhatsNewWindowController?

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

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutDown()
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
            presentWhatsNewIfNeeded()

        case .adoptExistingInstall:
            // Installed before the welcome window existed. Leave it exactly as it was,
            // login item included: `enableByDefaultIfNeeded` is a no-op for any install
            // whose first launch already applied the old default.
            LoginItemController().enableByDefaultIfNeeded()
            FirstRunExperience.markCompleted()
            // An install that has been running since before either window existed. It is
            // still an upgrade, so it hears what changed — just without being greeted.
            presentWhatsNewIfNeeded()

        case .welcome:
            // A new install starts life knowing everything this version has to say, so
            // its next launch must not open a What's New for the release it arrived on.
            // Stamped now rather than in `onFinish`, so quitting mid-welcome cannot leave
            // the install looking like an upgrade that missed a release.
            WhatsNewExperience.markSeen()
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

    /// Say what changed, once, after an update installs and relaunches.
    ///
    /// The version is stamped whatever the outcome — including when there is nothing to
    /// show, so a release that ships without notes still moves the mark forward instead
    /// of leaving every later launch re-asking the same question.
    @MainActor
    private func presentWhatsNewIfNeeded() {
        guard case let .show(notes) = WhatsNewExperience.decide() else {
            WhatsNewExperience.markSeen()
            return
        }
        // A release can ask to show the tour itself instead of describing it — see
        // `ReleaseNote.showsWelcome`.
        if notes.contains(where: \.revisitsWelcome) {
            presentWelcomeAgain()
            return
        }
        NSLog("Perch is showing What's New for \(notes.map { $0.version.description })")
        let whatsNew = WhatsNewWindowController(notes: notes)
        self.whatsNew = whatsNew
        whatsNew.onFinish = { [weak self] in
            WhatsNewExperience.markSeen()
            // Released on the next pass for the same reason the welcome window is:
            // dropping the last reference from inside its own callback would deallocate
            // the closure still running.
            DispatchQueue.main.async { self?.whatsNew = nil }
        }
        whatsNew.show()
    }

    /// Show an existing install the welcome window again, seeded with everything it
    /// already has.
    ///
    /// This window commits its answers on *any* dismissal, so the seeding is not a nicety:
    /// with fresh-install defaults, a returning user who glanced at it and clicked the red
    /// button would have Launch at Login switched back on and their edge selection
    /// replaced by Perch's. Seeded, doing nothing means nothing changes — the window can
    /// only alter what the user deliberately alters.
    @MainActor
    private func presentWelcomeAgain() {
        guard let controller else {
            WhatsNewExperience.markSeen()
            return
        }
        let loginItem = LoginItemController()
        let welcome = WelcomeWindowController(
            loginItemAvailable: loginItem.isAvailable,
            offeredEdges: FirstRunExperience.offerableEdges(),
            mode: .revisit,
            choices: WelcomeChoices(
                launchAtLogin: loginItem.isEnabled,
                edges: controller.currentEnabledEdges
            )
        )
        self.welcome = welcome
        NSLog("Perch is showing the welcome window again for this update")
        welcome.onFinish = { [weak self, weak controller] launchAtLogin, edges in
            if loginItem.isAvailable {
                loginItem.setEnabled(launchAtLogin)
            }
            WhatsNewExperience.markSeen()
            controller?.completeFirstRun(enabling: edges)
            DispatchQueue.main.async { self?.welcome = nil }
        }
        welcome.show()
    }

    // Perch has no Dock icon, so double-clicking the app in Finder is the user's
    // natural "where did it go?" gesture — use it to rescue a stranded shelf and
    // bring it back into view.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.handleReopen()
        return false
    }
}
