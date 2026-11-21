import Foundation

enum EdgeTabPreferenceMigration {
    static func run(defaults: UserDefaults = .standard) {
        if !defaults.bool(forKey: PerchSettings.edgeTabOffByDefaultMigrationCompleted) {
            defaults.set(false, forKey: PerchSettings.showsEdgeTab)
            defaults.set(true, forKey: PerchSettings.edgeTabOffByDefaultMigrationCompleted)
        }
        // The reminder was a hidden Labs switch, so almost nobody chose its off state.
        if !defaults.bool(forKey: PerchSettings.edgeReminderOnByDefaultMigrationCompleted) {
            defaults.set(true, forKey: PerchSettings.showsEdgeTab)
            defaults.set(true, forKey: PerchSettings.edgeReminderOnByDefaultMigrationCompleted)
        }
    }
}
