import AppKit
import Carbon.HIToolbox

/// A global shortcut: a key plus at least one of ⌘, ⌃ or ⌥ (⇧ alone would steal typing).
struct KeyCombo: Equatable, Codable {
    let keyCode: UInt32
    let modifiers: UInt
    /// What the key prints as, captured when recorded, so the label survives layouts.
    let key: String

    static let clipboardDefault = KeyCombo(
        keyCode: UInt32(kVK_ANSI_C), modifiers: [.command, .option], key: "C"
    )!

    static let allowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    init?(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, key: String) {
        let modifiers = modifiers.intersection(Self.allowedModifiers)
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        guard !Self.modifierKeyCodes.contains(keyCode) else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
        self.key = Self.specialKeyNames[keyCode] ?? key.uppercased()
        guard !self.key.isEmpty else { return nil }
    }

    init?(event: NSEvent) {
        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: event.modifierFlags,
            key: event.charactersIgnoringModifiers ?? ""
        )
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifierFlags.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifierFlags.contains(.option) { carbon |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    var displayString: String {
        let flags = modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + key
    }

    static func load(from defaults: UserDefaults = .standard) -> KeyCombo {
        guard let data = defaults.data(forKey: PerchSettings.clipboardHotKey),
              let combo = try? JSONDecoder().decode(KeyCombo.self, from: data)
        else { return .clipboardDefault }
        return combo
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: PerchSettings.clipboardHotKey)
    }

    private static let modifierKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command), UInt32(kVK_RightCommand), UInt32(kVK_Shift), UInt32(kVK_RightShift),
        UInt32(kVK_Option), UInt32(kVK_RightOption), UInt32(kVK_Control), UInt32(kVK_RightControl),
        UInt32(kVK_CapsLock), UInt32(kVK_Function)
    ]

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]
}
