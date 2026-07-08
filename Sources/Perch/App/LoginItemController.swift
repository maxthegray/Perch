import AppKit
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at Login" toggle.
///
/// Login-item registration only works when Perch is running as a real, signed `.app`
/// bundle (see `Scripts/build-app.sh`). When launched unbundled via `swift run`, there's
/// no bundle identifier, so `isAvailable` is false and the menu item is hidden.
@MainActor
final class LoginItemController {
    private static let defaultAppliedKey = "Perch.LaunchAtLoginDefaultApplied"
    private static let userChoiceKey = "Perch.LaunchAtLoginUserChoice"

    /// Whether launch-at-login can be controlled (i.e. we're a bundled app).
    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Whether Perch is currently registered to launch at login.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, recordUserChoice: Bool = true) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(true, forKey: Self.defaultAppliedKey)
            if recordUserChoice {
                UserDefaults.standard.set(enabled, forKey: Self.userChoiceKey)
            }
            return true
        } catch {
            NSLog("Perch login-item \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    /// Enable Launch at Login by default once, without re-enabling it after the user
    /// turns it off from Perch's menu.
    func enableByDefaultIfNeeded() {
        guard isAvailable else { return }
        guard UserDefaults.standard.object(forKey: Self.defaultAppliedKey) == nil else { return }
        guard UserDefaults.standard.object(forKey: Self.userChoiceKey) == nil else { return }

        if isEnabled {
            UserDefaults.standard.set(true, forKey: Self.defaultAppliedKey)
        } else {
            setEnabled(true, recordUserChoice: false)
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
