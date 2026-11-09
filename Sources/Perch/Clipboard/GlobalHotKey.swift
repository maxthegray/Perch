import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission. Call `invalidate()` to release it.
final class GlobalHotKey {
    private static let signature: OSType = 0x5052_4348 // "PRCH"
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Fails when macOS refuses the shortcut. Carbon does not report a clash with another
    /// app's hotkey, so this rarely fails in practice.
    init?(combo: KeyCombo, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.signature == GlobalHotKey.signature, pressed.id == hotKey.id else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installed == noErr else { return nil }

        let registered = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers, EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey
        )
        guard registered == noErr else {
            NSLog("Perch could not register \(combo.displayString) as a hotkey: \(registered)")
            invalidate()
            return nil
        }
    }

    func invalidate() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    deinit {
        invalidate()
    }
}
