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
