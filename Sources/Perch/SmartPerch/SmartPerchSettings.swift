import Foundation

/// The user-facing Smart Perch switch.
///
/// It gates only what Smart Perch *shows*: generated names on rows and ghosts, and
/// learned route offers. Recording is deliberately untouched — drops, classification,
/// OCR, and route history keep accumulating while the switch is off, so turning it
/// back on reveals everything Perch learned in the meantime rather than starting the
/// three-session count from zero.
enum SmartPerchSettings {
    static let enabledKey = "Perch.SmartPerchEnabled"

    /// Defaults to on: an unset value reads as true, matching the behavior every
    /// existing install already has.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}
