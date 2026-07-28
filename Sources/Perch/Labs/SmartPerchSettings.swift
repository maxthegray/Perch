import Foundation

/// The master Smart Perch switch. Off means the feature is never built: no database is
/// opened, no OCR worker runs, and nothing is recorded.
enum SmartPerchSettings {
    static let enabledKey = PerchSettings.smartPerchEnabled

    /// Ships off. Perch is a shelf first; the learning stack is opt-in.
    static var isEnabled: Bool {
        PerchSettings.flag(enabledKey, default: false)
    }
}

enum SmartPerchNamePreference {
    static func settingAfterSmartPerchChange(
        enabled: Bool,
        currentlyShowsNames: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if enabled {
            if currentlyShowsNames {
                defaults.removeObject(forKey: PerchSettings.smartPerchAutoEnabledNames)
            } else {
                defaults.set(true, forKey: PerchSettings.smartPerchAutoEnabledNames)
            }
            return true
        }

        let wasAutoEnabled = defaults.bool(forKey: PerchSettings.smartPerchAutoEnabledNames)
        defaults.removeObject(forKey: PerchSettings.smartPerchAutoEnabledNames)
        return wasAutoEnabled ? false : currentlyShowsNames
    }

    static func userChangedNames(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: PerchSettings.smartPerchAutoEnabledNames)
    }
}
