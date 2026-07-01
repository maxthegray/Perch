import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: ShelfController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let controller = try ShelfController()
            self.controller = controller
            controller.start()
            // Start Sparkle's background update checks.
            Updater.shared.start()
        } catch {
            NSLog("Perch failed to start: \(error)")
            NSApp.terminate(nil)
        }
    }
}
