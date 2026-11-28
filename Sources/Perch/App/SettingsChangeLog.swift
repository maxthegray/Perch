import Foundation

/// Records each Perch setting the user changes into `PerchLog.actions`, by diffing the
/// same snapshot the troubleshooting report prints.
@MainActor
final class SettingsChangeLog {
    private static let bookkeeping: Set<String> = [
        "ShelfMoveCount", "AvailableUpdateVersion", "LastSeenVersion"
    ]

    private var last: [String: String]
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        last = Self.values(Diagnostics.settingsSnapshot(defaults: defaults))
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Self.values(Diagnostics.settingsSnapshot(defaults: defaults))
                for line in Self.changes(from: self.last, to: current) {
                    PerchLog.action(line)
                }
                self.last = current
            }
        }
    }

    static func values(_ snapshot: [String]) -> [String: String] {
        Dictionary(snapshot.compactMap { line -> (String, String)? in
            guard let equals = line.firstIndex(of: "=") else { return nil }
            return (String(line[..<equals]), String(line[line.index(after: equals)...]))
        }, uniquingKeysWith: { _, new in new })
    }

    static func changes(from old: [String: String], to new: [String: String]) -> [String] {
        Set(old.keys).union(new.keys).sorted().compactMap { key in
            guard old[key] != new[key],
                  !bookkeeping.contains(key),
                  !key.hasSuffix("MigrationCompleted") else { return nil }
            return "setting changed: \(key)=\(new[key] ?? "(cleared)")"
        }
    }
}
