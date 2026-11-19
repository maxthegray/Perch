import Foundation
import os

/// The last messages Perch logged this run, kept in memory for the troubleshooting
/// report. The unified log redacts `NSLog` text as `<private>`, so it can't be read back.
enum PerchLog {
    struct Entry: Sendable {
        let date: Date
        let message: String
    }

    private static let capacity = 200
    private static let entries = OSAllocatedUnfairLock<[Entry]>(initialState: [])

    static func record(_ message: String) {
        entries.withLock { entries in
            entries.append(Entry(date: Date(), message: message))
            if entries.count > capacity {
                entries.removeFirst(entries.count - capacity)
            }
        }
    }

    static var recent: [Entry] {
        entries.withLock { $0 }
    }
}

/// Shadows Foundation's `NSLog` inside the Perch module so every message also lands in
/// `PerchLog`. Every call site passes a finished string, never a format.
func NSLog(_ message: String) {
    PerchLog.record(message)
    Foundation.NSLog("%@", message)
}
