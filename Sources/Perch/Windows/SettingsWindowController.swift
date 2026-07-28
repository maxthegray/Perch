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
    /// Which tab is up, and which half of Advanced it is showing. The preview shelf is
    /// only right for the Look half, and neither piece of state can be derived from the
    /// other — the tab bar cannot see inside the pane, and the pane is rebuilt often
    /// enough that it cannot be trusted to re-announce itself on every tab switch.
    private var selectedPaneLabel: String?
    private var advancedSection: AdvancedSettingsPane.Section = .look
    /// Held so the pane can be resized when its section changes; the three lists are
    /// different lengths and one shared height suits none of them.
    private weak var advancedPane: NSViewController?

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
            self.selectedPaneLabel = label
            self.reconcileAppearancePreview()
        }

        addPane(
            to: tabs, label: "General", symbol: "gearshape",
            size: NSSize(width: 560, height: 240),
            view: GeneralSettingsPane()
        )
        let advanced = NSHostingController(
            rootView: AdvancedSettingsPane(
                themeStore: themeStore,
                edgeSettings: edgeSettings,
                onSectionChanged: { [weak self] section in
                    guard let self else { return }
                    self.advancedSection = section
                    self.advancedPane?.preferredContentSize = NSSize(
                        width: 560,
                        height: section.preferredHeight
                    )
                    self.reconcileAppearancePreview()
                }
            )
        )
        advancedPane = advanced
        addPane(
            to: tabs, label: Self.advancedPaneLabel, symbol: "slider.horizontal.3",
            size: NSSize(width: 560, height: advancedSection.preferredHeight),
            controller: advanced
        )
        syncLabsPane(in: tabs)

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

        // Unlocking happens in the General pane and hiding happens in the Labs pane;
        // neither can reach the tab bar. Watch the flag instead so the tab appears on the
        // fifth click and disappears on Hide, rather than at the next launch.
        labsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self, weak tabs] _ in
            MainActor.assumeIsolated {
                guard let self, let tabs else { return }
                self.syncLabsPane(in: tabs)
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Adds or removes the Labs tab to match the unlock flag.
    private func syncLabsPane(in tabs: NSTabViewController) {
        let existing = tabs.tabViewItems.firstIndex { $0.label == Self.labsPaneLabel }

        guard LabsAccess.isUnlocked else {
            guard let existing else { return }
            // Removing the selected tab would leave the tab view with no selection and a
            // stale window title, so step back to General first.
            if tabs.selectedTabViewItemIndex == existing {
                tabs.selectedTabViewItemIndex = 0
            }
            tabs.removeTabViewItem(tabs.tabViewItems[existing])
            return
        }

        guard existing == nil else { return }
        addPane(
            to: tabs, label: Self.labsPaneLabel, symbol: "flask",
            size: NSSize(width: 560, height: 380),
            view: LabsSettingsPane(themeStore: themeStore)
        )
    }

    /// Summon or dismiss the preview shelf for the current tab and section. The preview
    /// exists so appearance options visibly tweak the real card, so it belongs to
    /// Advanced ▸ Look and nowhere else — it used to appear for the whole Advanced tab,
    /// including while the user was toggling shake-to-summon.
    private func reconcileAppearancePreview() {
        guard selectedPaneLabel == Self.advancedPaneLabel,
              advancedSection == .look,
              let frame = window?.frame
        else {
            onAppearancePaneDeselected?()
            return
        }
        onAppearancePaneSelected?(frame)
    }

    /// Reopening the window on a still-selected Advanced ▸ Look must re-summon the
    /// preview shelf; tab-switch callbacks alone would miss it.
    private func notifyIfAppearanceSelected() {
        guard let window, let tabs = window.contentViewController as? NSTabViewController,
              tabs.tabViewItems.indices.contains(tabs.selectedTabViewItemIndex)
        else { return }
        selectedPaneLabel = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
        reconcileAppearancePreview()
    }

    /// Each pane keeps a fixed preferred size so the toolbar tab style can animate the
    /// window between them; taller content scrolls inside its grouped form.
    private func addPane<V: View>(
        to tabs: NSTabViewController, label: String, symbol: String, size: NSSize, view: V
    ) {
        addPane(
            to: tabs,
            label: label,
            symbol: symbol,
            size: size,
            controller: NSHostingController(rootView: view)
        )
    }

    private func addPane(
        to tabs: NSTabViewController,
        label: String,
        symbol: String,
        size: NSSize,
        controller hosting: NSViewController
    ) {
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
