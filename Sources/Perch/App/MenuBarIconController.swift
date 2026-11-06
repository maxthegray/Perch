import AppKit
import SwiftUI

/// Training wheels for summoning the shelf: click to show or hide it, drop onto it to
/// stash, right-click for the rest. Stays until the user turns it off, which is one
/// click away in its own menu and in Settings.
@MainActor
final class MenuBarIconController: NSObject, NSWindowDelegate, NSDraggingDestination, NSMenuDelegate {
    /// Toggle the shelf. The point is the icon's bottom center, in screen coordinates.
    var onToggleShelf: ((NSPoint) -> Void)?
    var isShelfVisible: (() -> Bool)?
    var onDrop: ((NSPasteboard) -> Bool)?
    var onShowSettings: (() -> Void)?
    var onShowShortcuts: (() -> Void)?
    var onShowWelcome: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var iconView: NSImageView?
    private var defaultsObserver: NSObjectProtocol?
    private var retireOffer: NSPopover?

    static let retireOfferThreshold = 3

    func start() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncVisibility() }
        }
        syncVisibility()
    }

    private var isEnabled: Bool {
        PerchSettings.flag(PerchSettings.showsMenuBarIcon, default: true)
    }

    private func syncVisibility() {
        if isEnabled, statusItem == nil {
            install()
        } else if !isEnabled, let item = statusItem {
            retireOffer?.close()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: "bird", accessibilityDescription: "Perch")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        // Drawn by an image view rather than `button.image` so it can use the system
        // bounce symbol effect.
        let iconView = PassthroughImageView(image: image ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .labelColor
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        self.iconView = iconView
        button.setAccessibilityLabel("Perch")
        button.toolTip = "Perch"
        item.menu = makeMenu()
        button.window?.registerForDraggedTypes(ShelfDropView.acceptedTypes)
        button.window?.delegate = self
        statusItem = item
    }

    // MARK: Clicks

    private var iconBottomCenter: NSPoint {
        guard let button = statusItem?.button, let window = button.window else {
            return NSEvent.mouseLocation
        }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSPoint(x: frame.midX, y: frame.minY)
    }

    private let toggleShelfItem = NSMenuItem(title: "Show Shelf", action: nil, keyEquivalent: "")

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        toggleShelfItem.action = #selector(toggleShelf)
        toggleShelfItem.target = self
        menu.addItem(toggleShelfItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Shortcuts…", action: #selector(showShortcuts), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Welcome Screen…", action: #selector(showWelcome), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Quit Perch", action: #selector(quit), keyEquivalent: "")
            .target = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleShelfItem.title = isShelfVisible?() == true ? "Hide Shelf" : "Show Shelf"
    }

    @objc private func toggleShelf() {
        onToggleShelf?(iconBottomCenter)
        // After the menu has finished closing, or the popover has nothing to anchor to.
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem?.button else { return }
            self.offerRetirementIfEarned(from: button)
        }
    }

    @objc private func showShortcuts() { onShowShortcuts?() }
    @objc private func showSettings() { onShowSettings?() }
    @objc private func showWelcome() { onShowWelcome?() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func hideIcon() {
        UserDefaults.standard.set(true, forKey: PerchSettings.menuBarRetireOffered)
        UserDefaults.standard.set(false, forKey: PerchSettings.showsMenuBarIcon)
    }

    // MARK: Drag feedback

    /// A drag started somewhere: the shelf is popping out on its own, and the icon nods
    /// along so the two read as one thing.
    func bounce() {
        iconView?.addSymbolEffect(.bounce.down, options: .nonRepeating)
    }

    // MARK: Retirement

    private func offerRetirementIfEarned(from button: NSStatusBarButton) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PerchSettings.menuBarRetireOffered),
              defaults.integer(forKey: PerchSettings.selfSummonCount) >= Self.retireOfferThreshold
        else { return }
        defaults.set(true, forKey: PerchSettings.menuBarRetireOffered)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarRetireOfferView(
            onHide: { [weak self] in
                self?.retireOffer?.close()
                UserDefaults.standard.set(false, forKey: PerchSettings.showsMenuBarIcon)
            },
            onKeep: { [weak self] in self?.retireOffer?.close() }
        ))
        retireOffer = popover
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: Drops on the icon (NSWindowDelegate forwards the status window's drags)

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlight(true)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    func draggingExited(_ sender: NSDraggingInfo?) {
        highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlight(false)
        return onDrop?(sender.draggingPasteboard) ?? false
    }

    private func highlight(_ on: Bool) {
        statusItem?.button?.highlight(on)
    }
}

/// "You've got it" — offered once, after the user has summoned the shelf on their own.
struct MenuBarRetireOfferView: View {
    let onHide: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You've got the hang of it")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 6) {
                Keycap(glyph: "⌃")
                Text("at the edge, or just drag a file.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            HStack {
                Spacer()
                Button("Keep Icon", action: onKeep)
                Button("Hide Icon", action: onHide)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 270)
    }
}

/// The icon must never take the button's clicks.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
