import Foundation

enum LegacySmartPerchMigration {
    static let selectionKey = "Perch.UpdateTrack"
    static let enrollmentPendingKey = "Perch.SmartPerchEnrollmentPending"

    static func run(defaults: UserDefaults = .standard) {
        if defaults.bool(forKey: enrollmentPendingKey) {
            defaults.set(true, forKey: PerchSettings.smartPerchEnabled)
            let showsNames = defaults.object(forKey: PerchSettings.showsLabels) as? Bool ?? true
            defaults.set(
                SmartPerchNamePreference.settingAfterSmartPerchChange(
                    enabled: true,
                    currentlyShowsNames: showsNames,
                    defaults: defaults
                ),
                forKey: PerchSettings.showsLabels
            )
        }

        if defaults.object(forKey: PerchSettings.smartPerchEnabled) as? Bool == true {
            defaults.set(true, forKey: PerchSettings.smartPerchUnlocked)
        }

        defaults.removeObject(forKey: selectionKey)
        defaults.removeObject(forKey: enrollmentPendingKey)
    }
}
