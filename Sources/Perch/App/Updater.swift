import AppKit
import Sparkle

/// Wraps Sparkle's updater so the app can run automatic background checks and offer a
/// manual "Check for Updates…" command.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private let trackStore: UpdateTrackStore
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        trackStore = UpdateTrackStore()
        super.init()
    }

    /// Explicitly touch the singleton so its updater starts running at launch.
    func start() {
        _ = controller
    }

    /// Menu-driven check — shows Sparkle's UI even when already up to date.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func joinSmartPerch() {
        trackStore.enrollInSmartPerch()
        controller.updater.resetUpdateCycle()
        controller.checkForUpdates(nil)
    }

    func leaveSmartPerchAndDeleteData() {
        SmartPerchDataRemoval.request(defaults: trackStore.defaults)
        controller.updater.resetUpdateCycle()
        controller.updater.checkForUpdatesInBackground()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        trackStore.feedURLString
    }
}
