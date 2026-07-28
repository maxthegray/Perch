import Foundation

enum SmartPerchEnrollment {
    static func completeIfPending(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: UpdateTrackStore.smartEnrollmentPendingKey) else {
            return
        }

        defaults.set(true, forKey: PerchSettings.smartPerchEnabled)
        defaults.set(true, forKey: PerchSettings.smartPerchShowsSuggestions)
        defaults.set(true, forKey: PerchSettings.labsUnlocked)
        defaults.removeObject(forKey: UpdateTrackStore.smartEnrollmentPendingKey)
    }
}
