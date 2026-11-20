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
            delegate: delegate
        )
        do {
            try updater.start()
        } catch {
            NSLog("Perch could not start the updater: \(error)")
        }
        return updater
    }()

    /// SPUUpdater holds its delegate weakly.
    private let delegate = UpdaterDelegate()

    private init() {}

    /// A newer release the updater has seen but that isn't installed yet, whether or not
    /// the user declined it.
    var availableUpdate: SemanticVersion? {
        Self.pendingUpdate(
            found: UserDefaults.standard.string(forKey: PerchSettings.availableUpdateVersion),
            running: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    nonisolated static func pendingUpdate(found: String?, running: String?) -> SemanticVersion? {
        guard let found = found.flatMap(SemanticVersion.init),
              let running = running.flatMap(SemanticVersion.init),
              found > running
        else { return nil }
        return found
    }

    /// Explicitly touch the singleton so its updater starts running at launch.
    func start() {
        _ = updater
    }

    /// Menu-driven check — shows Sparkle's UI even when already up to date.
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// Remembers what each update check found, so a declined update stays offered.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        UserDefaults.standard.set(item.displayVersionString, forKey: PerchSettings.availableUpdateVersion)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        UserDefaults.standard.removeObject(forKey: PerchSettings.availableUpdateVersion)
    }
}
