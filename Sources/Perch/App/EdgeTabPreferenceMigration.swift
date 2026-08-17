import Foundation

enum EdgeTabPreferenceMigration {
    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(
            forKey: PerchSettings.edgeTabOffByDefaultMigrationCompleted
        ) else { return }

        defaults.set(false, forKey: PerchSettings.showsEdgeTab)
        defaults.set(
            true,
            forKey: PerchSettings.edgeTabOffByDefaultMigrationCompleted
        )
    }
}
