import AppKit
import Sparkle

/// Wraps Sparkle's updater so the app can run automatic background checks and offer a
/// manual "Check for Updates…" command. The feed URL and public EdDSA key live in
/// Info.plist (`SUFeedURL` / `SUPublicEDKey`); each update's signature is verified
/// against that key, so integrity holds regardless of the app's (ad-hoc) code signature.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true begins the scheduled background check on launch.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Explicitly touch the singleton so its updater starts running at launch.
    func start() {}

    /// Menu-driven check — shows Sparkle's UI even when already up to date.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
