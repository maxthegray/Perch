import AppKit
import SwiftUI

/// Owns the (lazily created) Settings window: a toolbar-tabbed preferences window in the
/// classic macOS style, one tab per pane. Perch is an accessory app, so showing the
/// window also activates the app so it can come forward and accept focus.
@MainActor
final class SettingsWindowController {
    /// The pane that carries the appearance controls, and therefore the one that summons
    /// the live preview shelf.
    private static let advancedPaneLabel = "Advanced"
    private static let labsPaneLabel = "Labs"

    private let themeStore: ThemeStore
    private let edgeSettings: EdgeSettings
    private var window: NSWindow?
    private var labsObserver: NSObjectProtocol?

    /// Fires when the Appearance pane comes up, with the settings window's frame.
    /// The shelf controller pops the real shelf out beside the window so the
    /// appearance options visibly tweak the actual card, not a mockup.
    var onAppearancePaneSelected: ((NSRect) -> Void)?

    /// Fires when the user leaves the Appearance pane for another tab, so the
    /// preview shelf clears right away instead of waiting for the window to close.
    var onAppearancePaneDeselected: (() -> Void)?

    /// Fires when the settings window closes, so a shelf that exists only as the
    /// Appearance preview can be cleared away with it.
    var onWindowClosed: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    init(themeStore: ThemeStore, edgeSettings: EdgeSettings) {
        self.themeStore = themeStore
        self.edgeSettings = edgeSettings
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            notifyIfAppearanceSelected()
            return
        }

        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.onPaneSelected = { [weak self] label in
            guard let self else { return }
            if label == Self.advancedPaneLabel {
                guard let frame = self.window?.frame else { return }
                self.onAppearancePaneSelected?(frame)
            } else {
                self.onAppearancePaneDeselected?()
            }
        }

        addPane(
            to: tabs, label: "General", symbol: "gearshape",
            size: NSSize(width: 560, height: 340),
            view: GeneralSettingsPane(edgeSettings: edgeSettings)
        )
        addPane(
            to: tabs, label: Self.advancedPaneLabel, symbol: "slider.horizontal.3",
            size: NSSize(width: 560, height: 820),
            view: AdvancedSettingsPane(themeStore: themeStore)
        )
        addLabsPaneIfUnlocked(to: tabs)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = tabs.tabViewItems.first?.label ?? "Settings"
        window.setContentSize(NSSize(width: 560, height: 240))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onWindowClosed?()
            }
        }

        // The unlock happens inside the General pane, which cannot reach the tab bar.
        // Watch the flag instead so the pane appears on the fifth click rather than on
        // the next launch.
        labsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self, weak tabs] _ in
            MainActor.assumeIsolated {
                guard let self, let tabs else { return }
                self.addLabsPaneIfUnlocked(to: tabs)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds the Labs tab once unlocked. Locking is not undone here: the flag is only ever
    /// set, and a pane that vanished under the user mid-session would be worse than one
    /// that stays until the next launch.
    private func addLabsPaneIfUnlocked(to tabs: NSTabViewController) {
        guard LabsAccess.isUnlocked,
              !tabs.tabViewItems.contains(where: { $0.label == Self.labsPaneLabel })
        else {
            return
        }
        addPane(
            to: tabs, label: Self.labsPaneLabel, symbol: "flask",
            size: NSSize(width: 560, height: 340),
            view: LabsSettingsPane(themeStore: themeStore)
        )
    }

    /// Reopening the window on a still-selected Advanced tab must re-summon the
    /// preview shelf; tab-switch callbacks alone would miss it.
    private func notifyIfAppearanceSelected() {
        guard let window, let tabs = window.contentViewController as? NSTabViewController,
              tabs.tabViewItems.indices.contains(tabs.selectedTabViewItemIndex),
              tabs.tabViewItems[tabs.selectedTabViewItemIndex].label == Self.advancedPaneLabel
        else { return }
        onAppearancePaneSelected?(window.frame)
    }

    /// Each pane keeps a fixed preferred size so the toolbar tab style can animate the
    /// window between them; taller content scrolls inside its grouped form.
    private func addPane<V: View>(
        to tabs: NSTabViewController, label: String, symbol: String, size: NSSize, view: V
    ) {
        let hosting = NSHostingController(rootView: view)
        hosting.preferredContentSize = size
        // NSTabViewController propagates the selected child's title up to the window;
        // untitled children would blank it to "Untitled" on every tab switch.
        hosting.title = label
        let item = NSTabViewItem(viewController: hosting)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        tabs.addTabViewItem(item)
    }
}

/// Mirrors the selected pane's name into the window title, System Settings-style,
/// and reports pane changes so the shelf can react (see `onAppearancePaneSelected`).
private final class SettingsTabViewController: NSTabViewController {
    var onPaneSelected: ((String) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label {
            view.window?.title = label
            onPaneSelected?(label)
        }
    }
}
