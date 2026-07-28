import Foundation

enum SmartPerchDataRemoval {
    static let pendingKey = "Perch.SmartPerchDataRemovalPending"

    private static let enabledKey = "Perch.SmartPerchEnabled"
    private static let suggestionsKey = "Perch.SmartPerchShowsSuggestions"
    private static let paneUnlockedKey = "Perch.LabsUnlocked"
    private static let showsLabelsKey = "Perch.ShowsLabels"

    static func request(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        UpdateTrackStore(defaults: defaults, bundledTrack: .smart).leaveSmartPerch()
        defaults.set(false, forKey: enabledKey)
        defaults.removeObject(forKey: suggestionsKey)
        defaults.set(false, forKey: paneUnlockedKey)
        let showsLabels = defaults.object(forKey: showsLabelsKey) as? Bool ?? true
        defaults.set(
            SmartPerchNamePreference.settingAfterSmartPerchChange(
                enabled: false,
                currentlyShowsNames: showsLabels,
                defaults: defaults
            ),
            forKey: showsLabelsKey
        )
        defaults.set(true, forKey: pendingKey)

        if let databaseURL = databaseURL ?? defaultDatabaseURL(fileManager: fileManager) {
            try? removeData(at: databaseURL, fileManager: fileManager)
        }
    }

    static func completeIfPending(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        databaseURL: URL? = nil
    ) {
        guard defaults.bool(forKey: pendingKey) else { return }
        guard let databaseURL = databaseURL ?? defaultDatabaseURL(fileManager: fileManager)
        else {
            return
        }

        do {
            try removeData(at: databaseURL, fileManager: fileManager)
            defaults.removeObject(forKey: pendingKey)
        } catch {
            NSLog("Perch could not finish removing Smart Perch data: \(error)")
        }
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

    private static func removeData(at databaseURL: URL, fileManager: FileManager) throws {
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
