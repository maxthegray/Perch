import Foundation

/// Whether the Smart Perch pane is available.
enum SmartPerchAccess {
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: PerchSettings.smartPerchUnlocked)
    }

    static let unlockClickCount = 5

    static func unlock() {
        guard !isUnlocked else { return }
        UserDefaults.standard.set(true, forKey: PerchSettings.smartPerchUnlocked)
    }

    static func lock() {
        UserDefaults.standard.set(false, forKey: PerchSettings.smartPerchUnlocked)
    }
}
