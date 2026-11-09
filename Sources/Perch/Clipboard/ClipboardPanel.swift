import AppKit
import Combine
import SwiftUI

/// Where the popup opens: its top-left corner just below-right of the pointer, pushed back
/// inside the screen's visible frame when that would spill off an edge.
enum ClipboardPanelPlacement {
    static let cursorOffset: CGFloat = 4

    static func frame(size: NSSize, cursor: NSPoint, visibleFrame: NSRect) -> NSRect {
        var origin = NSPoint(x: cursor.x + cursorOffset, y: cursor.y - cursorOffset - size.height)
        if origin.x + size.width > visibleFrame.maxX { origin.x = cursor.x - cursorOffset - size.width }
        if origin.y < visibleFrame.minY { origin.y = cursor.y + cursorOffset }
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }
}

/// A borderless popup that takes keyboard focus without activating Perch, so the app the
/// user was in stays frontmost and ⌘V goes straight back to it.
final class ClipboardPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: MagpieStyle.defaultStyle.size(forRows: 0)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class ClipboardPanelController {
    let model: ClipboardPanelModel
    private let panel = ClipboardPanel()
    private let effect = NSVisualEffectView()
    private var resultsObserver: AnyCancellable?

    var isVisible: Bool { panel.isVisible }

    init(model: ClipboardPanelModel) {
        self.model = model

        effect.frame = NSRect(origin: .zero, size: MagpieStyle.defaultStyle.size(forRows: 0))
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        let hosting = NSHostingView(rootView: ClipboardPanelView(model: model))
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.contentView = effect

        panel.onKeyDown = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false }
        }
        panel.onResignKey = { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Classic hugs its rows, so the popup grows and shrinks as the search filters,
        // keeping its top edge where it opened.
        resultsObserver = model.$results.sink { [weak self] results in
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                let size = self.model.style.size(forRows: results.count)
                let top = self.panel.frame.maxY
                self.panel.setFrame(
                    NSRect(x: self.panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                    display: true
                )
                self.panel.invalidateShadow()
            }
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let style = MagpieStyle.current
        model.prepareForShowing(style: style)
        effect.material = style.material
        effect.layer?.cornerRadius = style.cornerRadius
        let size = style.size(forRows: model.results.count)
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        panel.setFrame(
            ClipboardPanelPlacement.frame(size: size, cursor: cursor, visibleFrame: visible),
            display: false
        )
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 53: // Escape
            hide()
            return true
        case 125: // Down
            model.moveSelection(by: 1)
            return true
        case 126: // Up
            model.moveSelection(by: -1)
            return true
        case 36, 76: // Return, keypad Enter
            model.chooseSelected()
            return true
        case 51 where flags.contains(.option): // ⌥⌫
            model.deleteSelected()
            return true
        default:
            break
        }

        guard flags.contains(.command) else { return false }
        if let characters = event.charactersIgnoringModifiers, let digit = Int(characters), (1...9).contains(digit) {
            model.choose(at: digit - 1)
            return true
        }
        // Perch has no main menu, so the search field gets its editing shortcuts here.
        let actions: [String: Selector] = [
            "v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)),
            "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:)),
            "z": Selector(("undo:"))
        ]
        if let key = event.charactersIgnoringModifiers?.lowercased(), let action = actions[key] {
            return NSApp.sendAction(action, to: nil, from: panel)
        }
        if event.charactersIgnoringModifiers == "w" {
            hide()
            return true
        }
        return false
    }
}
