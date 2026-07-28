import AppKit
import Sparkle

/// Wraps Sparkle's updater so the app can run automatic background checks and offer a
/// manual "Check for Updates…" command.
@MainActor
final class Updater {
    static let shared = Updater()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private init() {}

    /// Explicitly touch the singleton so its updater starts running at launch.
    func start() {
        _ = controller
    }

    /// Menu-driven check — shows Sparkle's UI even when already up to date.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
