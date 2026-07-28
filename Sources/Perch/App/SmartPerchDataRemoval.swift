import Foundation

enum SmartPerchDataRemoval {
    static let pendingKey = "Perch.SmartPerchDataRemovalPending"

    static func markPending(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingKey)
    }

    static func completeIfPending(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        guard defaults.bool(forKey: pendingKey) else { return }
        guard let databaseURL = databaseURL ?? defaultDatabaseURL(fileManager: fileManager) else {
            finishPreferences(defaults: defaults)
            return
        }

        do {
            try removeNow(databaseURL: databaseURL, fileManager: fileManager)
            finishPreferences(defaults: defaults)
        } catch {
            NSLog("Perch could not finish removing Smart Perch data: \(error)")
        }
    }

    static func finishPreferences(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: PerchSettings.smartPerchEnabled)
        defaults.set(false, forKey: PerchSettings.smartPerchUnlocked)
        defaults.removeObject(forKey: PerchSettings.smartPerchAutoEnabledNames)
        defaults.removeObject(forKey: "Perch.SmartPerchShowsSuggestions")
        defaults.removeObject(forKey: LegacySmartPerchMigration.selectionKey)
        defaults.removeObject(forKey: LegacySmartPerchMigration.enrollmentPendingKey)
        defaults.removeObject(forKey: pendingKey)
    }

    private static func defaultDatabaseURL(fileManager: FileManager) -> URL? {
        try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        .appendingPathComponent("Perch", isDirectory: true)
        .appendingPathComponent("smart-perch.sqlite", isDirectory: false)
    }

    static func removeNow(
        databaseURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let paths = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal")
        ]

        for path in paths where fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }
}
