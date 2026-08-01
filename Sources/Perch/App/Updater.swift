import AppKit
import Sparkle

/// Wraps Sparkle's updater so the app can run automatic background checks and offer a
/// manual "Check for Updates…" command.
@MainActor
final class Updater {
    static let shared = Updater()

    /// Built by hand rather than through `SPUStandardUpdaterController` because that
    /// wrapper always installs Sparkle's own user driver, and Perch replaces one of its
    /// screens — see `PerchUpdateUserDriver`.
    private lazy var updater: SPUUpdater = {
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: PerchUpdateUserDriver(hostBundle: .main),
            delegate: nil
        )
        do {
            try updater.start()
        } catch {
            NSLog("Perch could not start the updater: \(error)")
        }
        return updater
    }()

    private init() {}

    /// Explicitly touch the singleton so its updater starts running at launch.
    func start() {
        _ = updater
    }

    /// Menu-driven check — shows Sparkle's UI even when already up to date.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
