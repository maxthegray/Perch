import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ShelfController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let controller = try ShelfController()
            self.controller = controller
            controller.start()
            LoginItemController().enableByDefaultIfNeeded()
            // Start Sparkle's background update checks.
            Updater.shared.start()
        } catch {
            NSLog("Perch failed to start: \(error)")
            NSApp.terminate(nil)
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
