import AppKit
import SwiftUI

/// Owns the (lazily created) Settings window: a toolbar-tabbed preferences window in the
/// classic macOS style, one tab per pane. Perch is an accessory app, so showing the
/// window also activates the app so it can come forward and accept focus.
@MainActor
final class SettingsWindowController {
    private static let shelfPaneLabel = "Shelf"
    private static let labsPaneLabel = "Labs"

    private let themeStore: ThemeStore
    private let edgeSettings: EdgeSettings
    private let smartPerch: SmartPerchCoordinator
    private let clipboard: ClipboardCoordinator
    private var window: NSWindow?
    private let collectedData = CollectedDataWindowController()
    private var labsObserver: NSObjectProtocol?
    /// Which tab is up. Only Shelf summons the live appearance preview.
    private var selectedPaneLabel: String?

    /// Fires when the Shelf pane comes up, with the settings window's frame.
    /// The shelf controller pops the real shelf out beside the window so the
    /// appearance options visibly tweak the actual card, not a mockup.
    var onAppearancePaneSelected: ((NSRect) -> Void)?

    /// Fires when the user leaves the Shelf pane for another tab, so the
    /// preview shelf clears right away instead of waiting for the window to close.
    var onAppearancePaneDeselected: (() -> Void)?

    /// Fires when the settings window closes, so a shelf that exists only as the
    /// Shelf preview can be cleared away with it.
    var onWindowClosed: (() -> Void)?
    private var closeObserver: NSObjectProtocol?

    init(
        themeStore: ThemeStore,
        edgeSettings: EdgeSettings,
        smartPerch: SmartPerchCoordinator,
        clipboard: ClipboardCoordinator
    ) {
        self.themeStore = themeStore
        self.edgeSettings = edgeSettings
        self.smartPerch = smartPerch
        self.clipboard = clipboard
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
            size: NSSize(width: 560, height: 260),
            view: GeneralSettingsPane(smartPerch: smartPerch) { [weak self] in
                self?.revealLabs()
            }
        )
        addPane(
            to: tabs, label: Self.shelfPaneLabel, symbol: "rectangle.3.group",
            size: NSSize(width: 580, height: 530),
            view: ShelfSettingsPane(themeStore: themeStore, edgeSettings: edgeSettings)
        )
        addPane(
            to: tabs, label: "Behavior", symbol: "cursorarrow.motionlines",
            size: NSSize(width: 580, height: 570),
            view: BehaviorSettingsPane(themeStore: themeStore)
        )
        addPane(
            to: tabs, label: "Files", symbol: "arrow.right",
            size: NSSize(width: 760, height: 350),
            view: FileSettingsPane()
        )
        addPane(
            to: tabs, label: "Magpie", symbol: "doc.on.clipboard",
            size: NSSize(width: 560, height: 290),
            view: MagpieSettingsPane(clipboard: clipboard) { [weak self] in
                guard let self else { return }
                self.collectedData.show(title: "Magpie", databaseURL: self.clipboard.databaseURL)
            }
        )
        syncLabsPane(in: tabs)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = tabs.tabViewItems.first?.label ?? "Settings"
        window.setContentSize(NSSize(width: 560, height: 260))
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

        // Settings written elsewhere (Smart Perch's own enable path) cannot reach the tab
        // controller. Watch the persisted access flag so the pane appears immediately.
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

    /// Unlocks Labs and brings its tab forward. Every feature inside stays off.
    private func revealLabs() {
        LabsAccess.unlock()
        guard let tabs = window?.contentViewController as? NSTabViewController else { return }
        syncLabsPane(in: tabs)
        if let index = tabs.tabViewItems.firstIndex(where: { $0.label == Self.labsPaneLabel }) {
            tabs.selectedTabViewItemIndex = index
        }
    }

    /// Adds or removes the Labs tab to match its access flag.
    private func syncLabsPane(in tabs: NSTabViewController) {
        let existing = tabs.tabViewItems.firstIndex {
            $0.label == Self.labsPaneLabel
        }

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
            view: LabsSettingsPane(smartPerch: smartPerch) { [weak self] in
                guard let self else { return }
                self.collectedData.show(title: "Smart Perch", databaseURL: self.smartPerch.databaseURL)
            }
        )
    }

    /// Summon or dismiss the preview shelf. It belongs only to Shelf, where every live
    /// appearance control and location choice now has one permanent home.
    private func reconcileAppearancePreview() {
        guard selectedPaneLabel == Self.shelfPaneLabel, let frame = window?.frame
        else {
            onAppearancePaneDeselected?()
            return
        }
        onAppearancePaneSelected?(frame)
    }

    /// Reopening the window on a still-selected Shelf tab must re-summon the
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
        to tabs: NSTabViewController,
        label: String,
        symbol: String,
        size: NSSize,
        view: V
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
