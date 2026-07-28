import Foundation

enum SmartPerchEnrollment {
    static func completeIfPending(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: UpdateTrackStore.smartEnrollmentPendingKey) else {
            return
        }

        defaults.set(true, forKey: PerchSettings.smartPerchEnabled)
        let showsLabels = defaults.object(forKey: PerchSettings.showsLabels) as? Bool ?? true
        defaults.set(
            SmartPerchNamePreference.settingAfterSmartPerchChange(
                enabled: true,
                currentlyShowsNames: showsLabels,
                defaults: defaults
            ),
            forKey: PerchSettings.showsLabels
        )
        defaults.set(true, forKey: PerchSettings.labsUnlocked)
        defaults.removeObject(forKey: UpdateTrackStore.smartEnrollmentPendingKey)
    }
}
