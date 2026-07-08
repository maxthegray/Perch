import AppKit

/// The shelf window: a non-activating panel that floats above ordinary app windows
/// on every Space, never takes key focus, and stays *below* the menu bar.
final class ShelfPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var canBecomeKey: Bool { false }

    private func configurePanel() {
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Shadow is user-toggleable and driven by ShelfController from ThemeStore. It
        // starts off because on a borderless translucent panel the native shadow renders
        // as a crisp dark line hugging the card, reading as a black outline.
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        // Needed so the host view's mouse-moved tracking (hover highlight + delete
        // button) fires while the panel is non-key.
        acceptsMouseMovedEvents = true
        // We drive reveal/hide ourselves (content-layer transform + alpha); keep AppKit's
        // default window animations from fighting it.
        animationBehavior = .none
    }
}
