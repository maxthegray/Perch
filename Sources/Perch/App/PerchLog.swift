import Foundation
import os

/// A fixed-size, thread-safe buffer of the newest log lines.
final class LogRing: Sendable {
    private let capacity: Int
    private let entries = OSAllocatedUnfairLock<[PerchLog.Entry]>(initialState: [])

    init(capacity: Int) {
        self.capacity = capacity
    }

    func record(_ message: String) {
        entries.withLock { entries in
            entries.append(PerchLog.Entry(date: Date(), message: message))
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    var recent: [PerchLog.Entry] {
        entries.withLock { $0 }
    }
}

/// The last messages Perch logged this run, kept in memory for the troubleshooting
/// report. The unified log redacts `NSLog` text as `<private>`, so it can't be read back.
enum PerchLog {
    struct Entry: Sendable {
        let date: Date
        let message: String
    }

    private static let main = LogRing(capacity: 200)
    /// What the recent-arrivals watcher saw and decided, kept apart so a burst of
    /// Downloads churn never evicts the failures in `main`.
    static let arrivals = LogRing(capacity: 40)
    /// What the user did: the shelf showing and hiding and why, drops, drag-outs,
    /// settings changes. Never file names or contents.
    static let actions = LogRing(capacity: 40)

    static func action(_ message: String) {
        actions.record(message)
    }

    static func record(_ message: String) {
        main.record(message)
    }

    static var recent: [Entry] {
        main.recent
    }
}

/// Shadows Foundation's `NSLog` inside the Perch module so every message also lands in
/// `PerchLog`. Every call site passes a finished string, never a format.
func NSLog(_ message: String) {
    PerchLog.record(message)
    Foundation.NSLog("%@", message)
}
