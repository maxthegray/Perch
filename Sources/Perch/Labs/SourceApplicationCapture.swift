import AppKit
import SmartPerchCore

/// Captures the app that was frontmost when an external drop reached Perch.
///
/// Perch is an accessory app with non-activating UI, so the source usually remains
/// frontmost throughout the drag. macOS does not guarantee source-process identity
/// for every drag, so this context is intentionally optional and best-effort.
enum SourceApplicationCapture {
    static func current() -> SourceApplicationContext? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let context = SourceApplicationContext(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.localizedName
        )
        guard context.bundleIdentifier != nil || context.displayName != nil else {
            return nil
        }
        return context
    }
}
