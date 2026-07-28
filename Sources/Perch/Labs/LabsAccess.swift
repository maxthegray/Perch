import Foundation

/// Whether the Labs pane is shown at all.
///
/// The experiments are not a selling point and not something a new user should have to
/// form an opinion about, so the tab does not exist until someone deliberately asks for
/// it — five clicks on the version number in General. Locked is the shipping state; the
/// features inside are off independently of this, so unlocking reveals switches rather
/// than turning anything on.
enum LabsAccess {
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: PerchSettings.labsUnlocked)
    }

    /// Clicks on the version row needed to reveal the pane.
    static let unlockClickCount = 5

    static func unlock() {
        guard !isUnlocked else { return }
        UserDefaults.standard.set(true, forKey: PerchSettings.labsUnlocked)
    }

    /// Anyone who had already switched Smart Perch on keeps it on — so they need a way to
    /// reach the switch again. Without this they would be left with a feature running and
    /// no visible control for it.
    ///
    /// Only an explicitly stored `true` counts. An install that never touched the toggle
    /// has no stored value and reads as off, which is the intended new default.
    static func unlockIfSmartPerchWasAlreadyOn() {
        guard !isUnlocked,
              UserDefaults.standard.object(
                forKey: PerchSettings.smartPerchEnabled
              ) as? Bool == true
        else {
            return
        }
        unlock()
    }
}
