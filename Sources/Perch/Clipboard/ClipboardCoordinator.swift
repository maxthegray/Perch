import AppKit
import ClipboardCore

/// The switch for Magpie, Perch's clipboard history. On by default; off holds no feature at all.
@MainActor
final class ClipboardCoordinator: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var hotKey: KeyCombo
    @Published private(set) var errorMessage: String?

    let databaseURL: URL
    private let pasteboard: NSPasteboard
    private var feature: ClipboardFeature?

    init(databaseURL: URL, pasteboard: NSPasteboard = .general) {
        self.databaseURL = databaseURL
        self.pasteboard = pasteboard
        hotKey = KeyCombo.load()
    }

    nonisolated static var isSwitchedOn: Bool {
        PerchSettings.flag(PerchSettings.clipboardEnabled, default: true)
    }

    func bootstrap() {
        if Self.isSwitchedOn { activate() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        UserDefaults.standard.set(enabled, forKey: PerchSettings.clipboardEnabled)
        enabled ? activate() : deactivate()
    }

    func setHotKey(_ combo: KeyCombo) {
        hotKey = combo
        combo.save()
        registerHotKey()
    }

    /// Lets the shortcut recorder hear the current shortcut instead of the popup opening.
    func suspendHotKey() {
        feature?.unregisterHotKey()
    }

    func resumeHotKey() {
        registerHotKey()
    }

    func clearHistory() {
        do {
            if let feature {
                try feature.clearHistory()
            } else {
                try ClipStore.removeFiles(at: databaseURL)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Magpie’s history could not be cleared."
        }
    }

    func shutDown() {
        feature?.shutDown()
    }

    private func activate() {
        guard feature == nil else { return }
        guard let feature = ClipboardFeature(databaseURL: databaseURL, pasteboard: pasteboard) else {
            UserDefaults.standard.set(false, forKey: PerchSettings.clipboardEnabled)
            errorMessage = "Magpie could not open its local database."
            return
        }
        self.feature = feature
        isEnabled = true
        registerHotKey()
    }

    private func deactivate() {
        feature?.shutDown()
        feature = nil
        isEnabled = false
        errorMessage = nil
    }

    private func registerHotKey() {
        guard let feature else { return }
        errorMessage = feature.registerHotKey(hotKey)
            ? nil
            : "Perch couldn’t use \(hotKey.displayString) as a shortcut. Pick a different one."
    }
}
