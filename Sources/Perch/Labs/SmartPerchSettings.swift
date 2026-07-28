import Foundation

/// The two Labs switches for Smart Perch.
///
/// These used to be a single switch, and conflating them is what made the feature
/// impossible to actually turn off: it gated only what Smart Perch *showed*, while
/// drops, classification, OCR, and route history kept accumulating underneath. Every
/// install therefore carried a database of where its files had been moved whether or not
/// the user ever wanted the feature.
///
/// Split into the two decisions that were hiding in there:
///
/// - ``isEnabled`` is the master. Off means Smart Perch is never built — no database
///   opened, no OCR worker, no per-drag route coordinators, nothing recorded.
/// - ``showsSuggestions`` decides only whether what Perch already learned is displayed.
///   Turning it off is the old behavior, now something the user opts into rather than
///   the silent default.
enum SmartPerchSettings {
    static let enabledKey = PerchSettings.smartPerchEnabled
    static let showsSuggestionsKey = PerchSettings.smartPerchShowsSuggestions

    /// Ships off. Perch is a shelf first; the learning stack is opt-in.
    static var isEnabled: Bool {
        PerchSettings.flag(enabledKey, default: false)
    }

    /// Only meaningful while ``isEnabled``. Defaults on, so switching Smart Perch on
    /// shows its work without a second trip to Settings. Off keeps learning running with
    /// nothing on screen — useful for building up the three-session count quietly.
    static var showsSuggestions: Bool {
        PerchSettings.flag(showsSuggestionsKey, default: true)
    }
}
