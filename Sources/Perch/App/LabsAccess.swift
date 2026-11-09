import Foundation

/// Whether the Labs pane is available. Unlocking only reveals the pane; every feature in it
/// keeps its own switch and stays off until the user turns it on.
enum LabsAccess {
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: PerchSettings.labsUnlocked)
    }

    static func unlock() {
        guard !isUnlocked else { return }
        UserDefaults.standard.set(true, forKey: PerchSettings.labsUnlocked)
    }
}
