import AppKit
import Combine
import Darwin
import SmartPerchCore
import SmartPerchVision
import UniformTypeIdentifiers

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    private static let preferredEdgeKey = PerchSettings.preferredShelfEdge
    private let panel: ShelfPanel
    private let windowController: ShelfWindowController
    private let holding: HoldingDirectory
    private let store: ItemStore
    private let ledger: ProvenanceLedger
    private let historyWindow: HistoryWindowController
    private let settingsWindow: SettingsWindowController
    private let snapshotter: PasteboardSnapshotter
    private let promiseMaterializer: FilePromiseMaterializer
    /// Smart Perch, or `nil` when the user has it switched off (and when its event log
    /// cannot be opened — a damaged log must not stop the shelf from launching). Nil is
    /// the whole feature being absent: no database, no OCR, nothing recorded.
    private var smart: SmartPerchFeature?
    /// Inert view-models when `smart` is nil. They stay on the controller so rebuilding
    /// the feature on a toggle cannot pull the bindings out from under the view tree.
    private let smartNames = SmartNameStore()
    private let routeSuggestions = RouteSuggestionStore()
    private let dropView: ShelfDropView
    private let hostView: ShelfHostView
    private let dockSnapPreview = DockSnapPreviewWindow()
    private var previewedDockTarget: DockSnapTarget?
    private var dockSnapPreviewHideTask: Task<Void, Never>?
    private let themeStore = ThemeStore()
    private let edgeSettings = EdgeSettings()
    /// Recent files in Downloads / Desktop offered as ghost rows and watched live.
    private let arrivals = RecentArrivals()
    private var edgeStrips: [EdgeStripWindow] = []
    private let mouseMonitor = MouseMonitor()
    private var openTask: Task<Void, Never>?
    private var retractTask: Task<Void, Never>?
    private var pointerInRegion = false
    /// Holds late hover/measurement callbacks off while a free shelf is fading away;
    /// otherwise switching to edge mode can flash the still-visible panel at its dock.
    private var dismissingFreeShelf = false
    /// Clears `dismissingFreeShelf` once the fade completes. Kept cancelable: a
    /// re-summon inside the window must lift the hold immediately, and a second
    /// dismissal must not have its hold ended early by the first one's timer.
    private var dismissingFreeShelfResetTask: Task<Void, Never>?
    /// True while a system drag is in flight; grows the empty drop target.
    private var dragActive = false
    /// True when the current drag (in "reveal while dragging" mode) opened the shelf.
    /// The chosen edge remains stable until the drag ends or the pointer explicitly
    /// enters another edge tab.
    private var revealedForDrag = false

    /// Whether the shelf should pop out at the nearest enabled edge the instant a drag
    /// starts (vs. waiting for the pointer to reach the edge tab). User-toggled; defaults on.
    private var revealOnDragStart: Bool {
        PerchSettings.flag(PerchSettings.revealOnDragStart, default: true)
    }
    /// Whether the shake-to-summon gesture is active. User-toggled; defaults on (an unset
    /// value reads as true), matching the original always-on behavior.
    private var shakeToSummonEnabled: Bool {
        PerchSettings.flag(PerchSettings.shakeToSummon, default: true)
    }
    /// Whether a free-floating shelf stays put (as the empty drop tile) after its last
    /// item leaves, instead of dismissing itself. User-toggled; defaults on.
    private var keepsEmptyFreeShelf: Bool {
        PerchSettings.flag(PerchSettings.keepEmptyShelf, default: true)
    }
    /// Whether free shelves preview and snap back into enabled edge docks.
    private var snapBackToEdgesEnabled: Bool {
        PerchSettings.flag(PerchSettings.snapBackToEdges, default: true)
    }
    /// Polls the cursor while the shelf is open so an empty shelf reliably retracts once
    /// the pointer leaves — see `startRetractWatcher`.
    private var retractWatcher: Task<Void, Never>?
    /// Tracks the last empty/non-empty state so open/retract only runs on a real flip.
    private var wasEmpty: Bool?
    /// Latest measured SwiftUI content height, used to size the window to fit.
    private var measuredContentHeight: CGFloat?
    /// Item count at the last store change, to tell removals from insertions.
    private var lastItemCount = 0
    /// The item snapshot emitted by `store.$items`. `@Published` emits before
    /// `store.items` is replaced, so width calculations during that callback must use
    /// this snapshot rather than the temporarily stale property.
    private var sizingItems: [StoredItem] = []
    /// True while a row-removal animation is in flight. The rows animate their shrink,
    /// so the measured height streams a new value every frame; acting on each one would
    /// snap-resize (and re-center) the window per frame — the visible "clunk". Instead
    /// the window animates once to the exact final frame and measured heights are
    /// ignored until the dust settles.
    private var removalResizeInFlight = false
    private var removalResizeTask: Task<Void, Never>?
    /// Invalidates queued insertion re-fits so one multi-item drop produces one window
    /// animation instead of several competing animations with intermediate targets.
    private var insertionResizeGeneration: UInt = 0
    /// Store insertion and recent-arrival removal are one visual row replacement during
    /// a drop. Combine publishes them separately; hold their layout reactions until
    /// both mutations have completed, then resize the panel once.
    private var dropLayoutMutationInFlight = false
    private var dropInsertionResizePending = false
    private struct GrabberResizeTransition {
        let startHeight: CGFloat
        let targetHeight: CGFloat
        let startProgress: CGFloat
        let targetProgress: CGFloat
        let bottom: CGFloat
    }
    /// Active handle reveal synchronized from the panel's real animated height.
    private var grabberResizeTransition: GrabberResizeTransition?
    /// Observes display add/remove/resolution changes so the edge tabs stay correct.
    private var screenObserver: NSObjectProtocol?
    private var preferredScreen: NSScreen?
    private var preferredEdge: ShelfEdge = .right
    /// Where the visible panel actually sits. `preferredScreen`/`preferredEdge` are the
    /// *next reveal* target and get retargeted by any brush over an edge tab's catch
    /// zone, so in-place resizes must use these instead — otherwise a resize can
    /// teleport an open shelf to whichever edge the pointer last passed.
    private var shownScreen: NSScreen?
    private var shownEdge: ShelfEdge = .right
    private var itemsCancellable: AnyCancellable?
    private var styleCancellable: AnyCancellable?
    private var sizePresetCancellable: AnyCancellable?
    private var stacksItemsCancellable: AnyCancellable?
    private var labelsCancellable: AnyCancellable?
    private var smartNamesCancellable: AnyCancellable?
    private var routeSuggestionsCancellable: AnyCancellable?
    private var smartPerchEnabledCancellable: AnyCancellable?
    private var grabHandleCancellable: AnyCancellable?
    private var shadowCancellable: AnyCancellable?
    private var edgeTabCancellable: AnyCancellable?
    private var arrivalsCancellable: AnyCancellable?
    private var arrivalNamesCancellable: AnyCancellable?
    /// Coalesces asynchronous OCR/arrival label changes so the text can settle before
    /// the outer panel smoothly adopts its new content-hugging width.
    private var asynchronousNameResizeTask: Task<Void, Never>?
    /// Coalesces the several writes/renames produced by one browser download.
    private var arrivalRefreshTask: Task<Void, Never>?
    /// A shelf opened only to advertise a new arrival goes away again after a short
    /// glance; adopting, pinning, locking, or hovering it hands control to normal UI.
    private var arrivalAutoHideTask: Task<Void, Never>?

    /// Where the shelf is currently anchored: docked to a screen edge, or free-floating
    /// at the cursor (shake-to-summon). The two coexist on the same panel.
    private enum RevealMode { case edge, free }
    private var revealMode: RevealMode = .edge
    /// Edge tabs only make sense while Perch is docked to an edge. Once the user tears
    /// it off or summons it at the cursor, the free-floating card is the drop target.
    private var usesEdgeDock: Bool { revealMode == .edge }
    /// In free mode, the card's top-left corner in screen coords. Persisted across content
    /// resizes (the card grows downward from here) and updated when the user drags it.
    private var freeTopLeft: NSPoint?
    /// The screen a free-floating shelf is pinned to (the one the summon happened on).
    private var summonScreen: NSScreen?
    /// The edge whose width rules the free card inherits: the edge it was torn off
    /// (drag-to-pin) or `.right` for cursor summons — so a pinned card keeps exactly
    /// the look it had docked (the notch card is wider than the side ones).
    private var freeSourceEdge: ShelfEdge = .right
    /// The docked frame captured when a drag-to-pin gesture starts. Non-nil while the
    /// user is dragging the card off its edge; it decides pin vs. snap-back at mouse-up
    /// and holds the auto-retract machinery off while the card is mid-flight.
    private var dragOutDockedFrame: NSRect?
    /// True while the free-floating shelf is locked in place ("Lock Position"): the
    /// grab handle hides and whole-card drags (and cursor summons) are refused, making
    /// the card a fixture — like another edge — until it's unlocked or closed.
    private var freeShelfLocked = false
    /// True while the visible free shelf exists only as the settings Appearance
    /// preview; closing the settings window clears it away again. Locking the shelf,
    /// re-summoning it, or storing an item in it adopts it as a real shelf.
    private var shelfIsSettingsPreview = false
    /// Observes user-initiated window moves so a dragged free shelf keeps its new origin.
    private var windowMoveObserver: NSObjectProtocol?
    /// Mirrors the panel's actual animated size into the dock preview frame-by-frame.
    private var windowResizeObserver: NSObjectProtocol?
    /// When snapped beside the system Dock, identifies which live end Perch follows.
    private var dockAttachment: DockSnapTargetKind?
    /// Streams the Dock's Accessibility position into the panel so both auto-hide
    /// animations share the same progress.
    private var dockTrackingTask: Task<Void, Never>?

    init() throws {
        if let rawEdge = UserDefaults.standard.string(
            forKey: Self.preferredEdgeKey
        ), let storedEdge = ShelfEdge(rawValue: rawEdge) {
            preferredEdge = storedEdge
            shownEdge = storedEdge
        }
        holding = try HoldingDirectory.standard()
        store = ItemStore(holding: holding)
        ledger = ProvenanceLedger(holding: holding)
        historyWindow = HistoryWindowController(ledger: ledger)
        settingsWindow = SettingsWindowController(themeStore: themeStore, edgeSettings: edgeSettings)
        snapshotter = PasteboardSnapshotter(holding: holding)
        promiseMaterializer = FilePromiseMaterializer()
        panel = ShelfPanel(contentRect: Self.initialPanelFrame())
        windowController = ShelfWindowController(panel: panel)
        dropView = ShelfDropView(frame: panel.contentView?.bounds ?? .zero)
        hostView = ShelfHostView(
            store: store,
            themeStore: themeStore,
            ledger: ledger,
            arrivals: arrivals,
            smartNames: smartNames,
            routeSuggestions: routeSuggestions
        )
        dropView.autoresizingMask = [.width, .height]
        // Layer-backed so the reveal/hide can animate a content-layer transform.
        dropView.wantsLayer = true
        dropView.dropHandler = self

        // Pin the host to fill the content view exactly (constraints, not autoresizing,
        // so it can't drift when the window resizes to fit its contents).
        hostView.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            hostView.topAnchor.constraint(equalTo: dropView.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor)
        ])
        panel.contentView = dropView

        hostView.onRecordSuccessfulRoutes = { [weak self] routes in
            self?.smart?.recordSuccessfulRoutes(routes)
        }

        // "Close Shelf" in the context menu dismisses the free shelf without removing
        // any stored items.
        hostView.onCloseFreeShelf = { [weak self] in self?.dismissFreeShelf() }

        // An empty tile can also be dismissed by clicking its body — unless it's locked
        // in place, which makes it a fixture that ignores stray clicks. (A press that
        // moves is a drag, not a click; the host view already tells those apart.)
        hostView.onDismissEmptyFree = { [weak self] in
            guard let self, !self.freeShelfLocked else { return }
            self.dismissFreeShelf()
        }

        // Deleting the last item hides the card before the store empties, so the
        // empty-state swap happens off-screen instead of flashing mid-dismissal.
        // (Unless a free shelf is set to stay when empty — then it remains on screen
        // and shrinks to the empty tile in place.)
        hostView.onWillRemoveLastItem = { [weak self] in
            guard let self else { return }
            if self.revealMode == .free {
                guard !self.keepsEmptyFreeShelf else { return }
                self.dismissFreeShelf()
            } else {
                self.hideShelf(animated: true)
            }
        }

        // Dragging the card with the configured gesture (handle or Command-drag) moves
        // the whole card. From an edge it tears the docked shelf off: past a small
        // distance it pins where it's dropped as a free-floating shelf; otherwise it
        // snaps back. A free shelf moves freely unless it is released near an enabled
        // dock, where it snaps home and resumes normal edge behavior.
        // A free shelf stays movable in either gesture mode unless the user explicitly
        // locks it in place.
        hostView.canBeginShelfDrag = { [weak self] in
            guard let self, self.panel.isVisible else { return false }
            if self.revealMode == .free { return !self.freeShelfLocked }
            return true
        }

        // "Lock Position" on a free shelf: freeze it where it stands (bar hidden, no
        // card drags) until unlocked or closed.
        hostView.onToggleLock = { [weak self] in
            self?.toggleFreeShelfLock()
        }
        hostView.onShelfDragBegan = { [weak self] in
            guard let self else { return }
            self.detachFromSystemDock(makeVisible: false)
            self.clearDockSnapPreview()
            if self.revealMode == .edge {
                self.dragOutDockedFrame = self.panel.frame
            }
            self.cancelOpen()
            self.cancelRetract()
        }
        hostView.onShelfDragMoved = { [weak self] in
            self?.updateDockSnapPreview()
        }
        hostView.onShelfDragEnded = { [weak self] in
            self?.shelfDragDidEnd()
        }

        hostView.onCardHoverChanged = { [weak self] hovered in
            self?.resizeForGrabberHover(hovered)
        }

        hostView.onContextMenuClosed = { [weak self] in
            self?.contextMenuDidClose()
        }

        hostView.onAcceptFilenameSuggestion = { [weak self] item, suggestion in
            self?.acceptFilenameSuggestion(suggestion, for: item)
        }
        hostView.onDismissFilenameSuggestion = { [weak self] item in
            self?.dismissFilenameSuggestion(for: item)
        }
        hostView.onFileItemAtSuggestedRoute = { [weak self] item in
            self?.fileItemAtSuggestedRoute(item)
        }

        // Grow/shrink the window to the SwiftUI content's actual measured height.
        hostView.onContentHeight = { [weak self] height in
            self?.contentHeightDidChange(height)
        }

        hostView.onShowHistory = { [weak self] in
            self?.historyWindow.show()
        }

        hostView.onShowSettings = { [weak self] in
            self?.settingsWindow.show()
        }

        // Recent downloads can be adopted individually or as one temporal session.
        hostView.onAdoptArrival = { [weak self] offer, session in
            self?.adoptArrival(offer, from: session)
        }
        hostView.onAdoptArrivalSession = { [weak self] session in
            self?.adoptArrivalSession(session) ?? []
        }
        hostView.onExpandArrivalSession = { [weak self] session in
            self?.expandArrivalSession(session)
        }
        hostView.onDismissArrival = { [weak self] ghost in
            self?.dismissArrival(ghost)
        }

        // A file put back where it came from must not bounce straight back as an offer.
        store.onFilesRestored = { [weak self] urls in
            self?.arrivals.excludePermanently(urls.map(\.path))
        }

        // Appearance settings preview: pop the real shelf out beside the settings
        // window so the options visibly tweak the actual card. Never summons over an
        // existing shelf (visible shelves — locked ones included — already preview).
        settingsWindow.onAppearancePaneSelected = { [weak self] windowFrame in
            guard let self, !self.panel.isVisible else { return }
            self.summonAtCursor(NSPoint(x: windowFrame.maxX + 72, y: windowFrame.maxY - 16))
            self.shelfIsSettingsPreview = true
        }

        // The preview shelf leaves when the Appearance tab is deselected or the
        // settings window closes — unless the user adopted it in the meantime
        // (locked it or put something on it).
        settingsWindow.onAppearancePaneDeselected = { [weak self] in
            self?.clearSettingsPreviewShelf()
        }
        settingsWindow.onWindowClosed = { [weak self] in
            self?.clearSettingsPreviewShelf()
        }

        // Reinstall the edge tabs whenever the user enables/disables an edge dock.
        edgeSettings.onChange = { [weak self] in
            self?.rebuildEdgeStrips()
        }

        // Someone who already turned Smart Perch on keeps it, and needs the pane it lives
        // in to still be reachable.
        LabsAccess.unlockIfSmartPerchWasAlreadyOn()

        // Build Smart Perch only if the user has it on. Everything above this line is the
        // shelf, and works identically whether or not the feature exists. The stored
        // shelf has not been loaded yet, so `start` does the initial read.
        reconcileSmartPerchFeature(loadingExistingState: false)
    }

    /// Construct or tear down Smart Perch to match the master switch.
    ///
    /// Turning it off releases the event log and the OCR worker instead of leaving them
    /// running behind a hidden UI, which is the whole point of the switch. Turning it on
    /// re-reads what was learned previously — the database is kept on disk, so the
    /// three-session count does not restart.
    private func reconcileSmartPerchFeature(loadingExistingState: Bool = true) {
        let shouldBeActive = SmartPerchSettings.isEnabled
        guard shouldBeActive != (smart != nil) else { return }

        guard shouldBeActive else {
            smart?.shutDown()
            smart = nil
            smartNames.reset()
            routeSuggestions.replace(with: [:])
            arrivals.clearSmartNames()
            hostView.routeLearningActive = false
            scheduleAsynchronousNameResize()
            return
        }

        smart = SmartPerchFeature(
            databaseURL: holding.smartEventLogFile,
            smartNames: smartNames,
            routeSuggestions: routeSuggestions,
            arrivals: arrivals,
            currentItems: { [weak self] in self?.store.items ?? [] }
        )
        hostView.routeLearningActive = smart != nil
        guard loadingExistingState else { return }
        smart?.registerStoredScreenshotPresentations()
        smart?.loadFilenameSuggestions()
        smart?.refreshRouteSuggestions()
        smart?.prepareArrivalSmartNames()
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        do {
            try ShelfPersistenceLoader.load(store: store, ledger: ledger)
            smart?.registerStoredScreenshotPresentations()
            NSLog("Perch loaded \(store.items.count) stored item(s)")
        } catch {
            NSLog("Perch failed to load stored items: \(error)")
        }
        smart?.loadFilenameSuggestions()
        smart?.refreshRouteSuggestions()

        // Panel geometry is app-computed (a floating card), not user-movable, so we
        // always use the freshly computed frame rather than a stale persisted one.
        windowController.hide(animated: false)
        installEdgeStripIfNeeded()

        // Rebuild the edge tabs when displays are added/removed or change resolution,
        // so they never sit at stale positions or on a screen that no longer exists.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildEdgeStrips() }
        }

        // During a drag, advertise and reveal the shelf's established dock. Choosing a
        // target from the drag's starting point made screenshot drags (which begin in
        // the lower-right corner) pull a left-docked shelf across the screen.
        mouseMonitor.onDragSessionChange = { [weak self] active in
            guard let self else { return }
            self.setDragActive(active)
            if active {
                if self.usesEdgeDock {
                    self.showHomeTab()
                } else {
                    self.setTabsShown(false)
                }
                if self.usesEdgeDock, self.revealOnDragStart {
                    self.revealForDrag()
                }
            } else {
                self.setTabsShown(false)
                self.dragDidEnd()
            }
        }
        mouseMonitor.onDragMoved = { [weak self] _ in
            guard let self else { return }
            if self.usesEdgeDock {
                self.showHomeTab()
            } else {
                self.setTabsShown(false)
            }
        }
        // Shake the cursor to summon the shelf right where the pointer is (when enabled).
        mouseMonitor.onSummonAtCursor = { [weak self] point in
            guard let self, self.shakeToSummonEnabled else { return }
            self.summonAtCursor(point)
        }
        mouseMonitor.start()

        arrivals.startWatching { [weak self] in
            self?.arrivalDirectoryDidChange()
        }

        // Keep a dragged free shelf's chosen position: when the user moves the panel via
        // the grab handle, remember its new top-left so content resizes grow from there.
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.captureFreeOrigin() }
        }
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // The observer is explicitly delivered on the main queue; stay synchronous
            // with AppKit's resize tick so the outline cannot trail the panel by a frame.
            MainActor.assumeIsolated {
                self?.syncGrabberRevealToLivePanelSize()
                self?.syncDockPreviewToLivePanelSize()
            }
        }

        // Resize the card to hug its contents on every change, and stay open while it
        // holds items / retract when empty. Subscribing fires immediately with the
        // loaded items.
        itemsCancellable = store.$items
            .sink { [weak self] items in
                self?.shelfItemsDidChange(items)
            }

        // Switching styles changes the card's metrics — the compact/empty width is
        // derived from the theme's padding + icon size, and row heights differ — so
        // re-fit the open window. Same willSet/next-pass dance as the labels toggle;
        // the old theme's measured height is dropped so the new theme's estimate
        // drives the re-fit until SwiftUI reports the fresh measurement.
        styleCancellable = themeStore.$style
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.measuredContentHeight = nil
                self?.resizeToFitVisible()
            }

        // Size is one discrete choice now rather than two sliders streaming values, so
        // this re-fit animates: there is no thumb for the card to track. Changing it does
        // not change the content's natural height (the height floor is pure window
        // frame), so the measured height stays valid. Same willSet/next-pass dance as the
        // others.
        sizePresetCancellable = themeStore.$sizePreset
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resizeToFitVisible()
            }
        stacksItemsCancellable = themeStore.$stacksItems
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // The natural height switches between a full list and a one-row deck.
                // Drop the old measurement so the matching estimate drives the resize
                // until SwiftUI reports the new layout.
                self?.measuredContentHeight = nil
                self?.resizeToFitVisible()
            }

        // Toggling names on/off changes the card's width — re-fit the open window.
        // `@Published` emits on willSet, so hop to the next main-queue pass; resizing
        // synchronously would read the OLD `showsLabels` and keep the stale width.
        labelsCancellable = themeStore.$showsLabels
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resizeToFitVisible()
            }

        // OCR/window-context names arrive after the item itself. Re-fit once the label
        // projection changes so the panel follows the generated name instead of keeping
        // the width of the temporary screenshot filename.
        smartNamesCancellable = smartNames.$suggestionsByItemID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAsynchronousNameResize()
            }

        // Both Smart Perch switches live in UserDefaults (written by the settings pane's
        // @AppStorage, like every other toggle). The master one builds or tears the
        // feature down; the other only mirrors into the presentation stores so flipping
        // it re-renders the rows immediately.
        smartPerchEnabledCancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reconcileSmartPerchFeature()
                self?.applySmartPerchEnabled()
            }

        // A learned route reserves a second trailing slot, so the card's width follows
        // suggestions appearing and being resolved. Same deferred re-fit as Smart Names.
        routeSuggestionsCancellable = routeSuggestions.$suggestionsByItemID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAsynchronousNameResize()
            }

        // Showing/hiding the grab handle changes the card's height by the handle strip —
        // same willSet/next-pass dance as the labels toggle. The stale measured height
        // (still including/excluding the old strip) is dropped so the estimate drives
        // one animated re-fit instead of waiting for the snap.
        grabHandleCancellable = themeStore.$showsGrabHandle
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // @Published emits before the stored value changes. Reconcile on the
                // next main pass so disabling while hovered animates the live handle
                // lane closed (and enabling while hovered opens it) from the new state.
                DispatchQueue.main.async { [weak self] in
                    self?.reconcileGrabberForCurrentState()
                }
            }

        // The native window shadow is user-toggleable; apply the stored value now and on
        // every change. Fires immediately (no dropFirst) so the panel matches the setting
        // at launch.
        shadowCancellable = themeStore.$showsShadow
            .sink { [weak self] shows in
                self?.panel.hasShadow = shows
            }

        // Flipping the edge tab off mid-drag must fade the handle out right away (and
        // flipping it on must bring it back), so reconcile against the live drag state.
        // Deferred to the next main pass because @Published emits before the new value
        // is stored, and `showHomeTab`/`setTabsShown` read it.
        edgeTabCancellable = themeStore.$showsEdgeTab
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.dragActive {
                    self.showHomeTab()
                } else {
                    self.setTabsShown(false)
                }
            }

        // Ghost rows appearing/leaving change the card's height (and, when empty, its
        // width). Same willSet/next-pass dance as the toggles above.
        arrivalsCancellable = arrivals.$visibleGhosts
            .dropFirst()
            .sink { [weak self] _ in
                guard let self,
                      !self.dragActive,
                      !self.dropLayoutMutationInFlight else {
                    return
                }
                self.resizeToFitVisible()
            }
        arrivalNamesCancellable = arrivals.$smartNamesByPath
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleAsynchronousNameResize()
            }

    }

    // MARK: Recent arrivals (ghost rows)

    /// Re-scan the watched folders for offerable files. Called on each fresh reveal
    /// (`markRevealed` spends one of every shown file's limited offer chances) and after
    /// mutations that change what should be offered.
    private func refreshArrivals(markRevealed: Bool = false) {
        arrivals.refresh(excluding: arrivalExclusions(), markRevealed: markRevealed)
        smart?.prepareArrivalSmartNames()
    }

    /// A watched folder changed. Wait for Chrome's temporary download + rename burst
    /// to settle, then update a visible shelf or briefly reveal a hidden one.
    private func arrivalDirectoryDidChange() {
        arrivalRefreshTask?.cancel()
        arrivalRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }

            let previousIDs = Set(
                self.arrivals.sessions.flatMap(\.offers).map(\.id)
            )
            self.refreshArrivals()
            let newIDs = Set(
                self.arrivals.sessions.flatMap(\.offers).map(\.id)
            ).subtracting(previousIDs)
            guard !newIDs.isEmpty else { return }

            if self.panel.isVisible {
                // Includes locked free shelves: they never re-enter a reveal path, so
                // the watcher is what makes their ghost rows appear and resize in place.
                self.resizeToFitVisible()
                return
            }

            self.refreshArrivals(markRevealed: true)
            guard !self.arrivals.visibleGhosts.isEmpty else { return }
            self.revealAtPreferredEdge()
            self.scheduleArrivalAutoHide()
        }
    }

    private func scheduleArrivalAutoHide() {
        arrivalAutoHideTask?.cancel()
        arrivalAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            guard self.panel.isVisible,
                  self.shouldAutomaticallyRetractEmptyShelf(
                    pointerInKeepAliveRegion: self.pointerInRegion
                  )
            else { return }
            self.hideShelf(animated: true)
            self.arrivalAutoHideTask = nil
        }
    }

    /// Paths the shelf must never offer: files Perch itself recently vended into a
    /// folder (ledger destinations), and the recorded origins of items currently
    /// aboard (a copy-fallback stash leaves the original in place).
    private func arrivalExclusions() -> Set<String> {
        var excluded = Set<String>()
        let cutoff = Date().addingTimeInterval(-RecentArrivals.window - 60)
        for entry in ledger.entries where entry.vendedAt > cutoff {
            excluded.insert(entry.destination)
        }
        for item in store.items {
            guard let origins = item.metadata.originPaths else { continue }
            excluded.formUnion(origins.values)
        }
        return excluded
    }

    /// Bring an offered file aboard: move it into a fresh item directory (Finder-drop
    /// semantics — ownership moves, origin recorded so ✕ can put it back; copy fallback
    /// if the move is refused) and insert the item at the front.
    @discardableResult
    private func adoptArrival(
        _ offer: ArrivalOffer,
        from session: ArrivalSession,
        refreshAfterAdoption: Bool = true,
        recordsInteraction: Bool = true
    ) -> StoredItem? {
        let fileManager = FileManager.default
        let prefetchedOCRResult = smart?.takeArrivalAnalysis(forPath: offer.id)
        guard fileManager.fileExists(atPath: offer.url.path) else {
            refreshArrivals()
            return nil
        }

        let directory = store.newItemDirectory()
        let filesDir = directory.url.appendingPathComponent("files", isDirectory: true)
        let destination = filesDir.appendingPathComponent(offer.name, isDirectory: false)
        var originPaths: [String: String]? = [offer.name: offer.url.path]
        do {
            do {
                try fileManager.moveItem(at: offer.url, to: destination)
            } catch {
                NSLog("Perch could not move arrival \(offer.url.path) (\(error)); copying instead")
                try fileManager.copyItem(at: offer.url, to: destination)
                originPaths = nil
            }
        } catch {
            NSLog("Perch failed to adopt arrival \(offer.url.path): \(error)")
            try? fileManager.removeItem(at: directory.url)
            return nil
        }

        let contentType = (try? destination.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: destination.pathExtension)
        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(),
            title: offer.name,
            representations: [],
            backingFileNames: [offer.name],
            primaryFileType: contentType?.identifier,
            originPaths: originPaths
        )
        let metaURL = directory.url.appendingPathComponent("meta.json", isDirectory: false)
        do {
            try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)
        } catch {
            NSLog("Perch failed to persist adopted arrival metadata: \(error)")
        }

        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        registerScreenshotPresentationIfNeeded(for: item)
        store.insert(item, at: nil)
        recordSmartDrop(
            item,
            context: DropRecordingContext(
                batchID: session.id,
                occurredAt: metadata.createdAt,
                sourceApplication: nil
            ),
            payloadKind: .recentArrival,
            screenshotCaptureContexts: [offer.screenshotCaptureContext],
            prefetchedOCRResults: [prefetchedOCRResult]
        )
        if recordsInteraction {
            recordArrivalSessionInteraction(
                session,
                action: .adoptedOne,
                affectedFileCount: 1
            )
        }
        // The copy-fallback case leaves the original in the folder; the origin-path
        // exclusion keeps it from being re-offered.
        if refreshAfterAdoption {
            refreshArrivals()
        }
        NSLog("Perch adopted arrival \(offer.name)")
        return item
    }

    private func adoptArrivalSession(_ session: ArrivalSession) -> [StoredItem] {
        // Each individual insert goes to the front, so process oldest-first to leave
        // the session's newest-first presentation order intact on the shelf.
        let adopted = session.offers.reversed().compactMap { offer in
            adoptArrival(
                offer,
                from: session,
                refreshAfterAdoption: false,
                recordsInteraction: false
            )
        }
        refreshArrivals()
        guard !adopted.isEmpty else { return [] }
        recordArrivalSessionInteraction(
            session,
            action: .adoptedAll,
            affectedFileCount: adopted.count
        )
        return adopted
    }

    private func expandArrivalSession(_ session: ArrivalSession) {
        arrivals.expand(session)
        smart?.prepareArrivalSmartNames()
        recordArrivalSessionInteraction(
            session,
            action: .expanded,
            affectedFileCount: 0
        )
    }

    private func dismissArrival(_ ghost: ArrivalGhost) {
        let session = ghost.session
        switch ghost {
        case let .offer(offer, _):
            arrivals.dismiss(offer)
            recordArrivalSessionInteraction(
                session,
                action: .dismissedOne,
                affectedFileCount: 1
            )
        case .summary:
            arrivals.dismiss(session)
            recordArrivalSessionInteraction(
                session,
                action: .dismissedAll,
                affectedFileCount: session.offers.count
            )
        }
    }

    private func recordArrivalSessionInteraction(
        _ session: ArrivalSession,
        action: ArrivalSessionAction,
        affectedFileCount: Int
    ) {
        smart?.recordArrivalSessionInteraction(
            session,
            action: action,
            affectedFileCount: affectedFileCount
        )
    }

    /// Take a generated name the user accepted. Smart Perch decides whether the rename is
    /// still valid and records the outcome; the rename itself is the store's job, so the
    /// two halves meet here rather than giving the feature a handle on the shelf.
    private func acceptFilenameSuggestion(
        _ proposedFilename: String,
        for item: StoredItem
    ) {
        guard let smart,
              let rename = smart.plannedRename(of: item, to: proposedFilename)
        else {
            return
        }

        do {
            let renamedItem = try store.renameSingleBackingFile(
                of: item,
                to: proposedFilename
            )
            guard let acceptedFilename = renamedItem.metadata.backingFileNames.first else {
                return
            }
            smart.didAcceptRename(rename, acceptedFilename: acceptedFilename)
        } catch {
            NSLog("Perch could not rename \(item.metadata.title) to \(proposedFilename): \(error)")
        }
    }

    private func dismissFilenameSuggestion(for item: StoredItem) {
        smart?.dismissFilenameSuggestion(for: item)
    }

    /// Carry out a learned route: move the item's files into the folder it has always
    /// gone to, then let Smart Perch record the trip.
    private func fileItemAtSuggestedRoute(_ item: StoredItem) {
        guard let smart, let filing = smart.beginFilingAtSuggestedRoute(item) else {
            return
        }

        let moved = store.fileItems([item], into: filing.folder)
        guard !moved.isEmpty else {
            smart.abandonFiling(filing)
            return
        }

        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        smart.didFileAtSuggestedRoute(filing)
    }

    /// Push the "Show suggestions" switch into the presentation stores. Learning keeps
    /// running while it is off, so turning it on shows what was learned in the meantime.
    /// The master switch is a different question — it decides whether Smart Perch was
    /// built at all, and is handled where the feature is constructed.
    private func applySmartPerchEnabled() {
        let showsSuggestions = SmartPerchSettings.showsSuggestions
        guard showsSuggestions != smartNames.isEnabled
                || showsSuggestions != routeSuggestions.isEnabled
        else {
            // Any defaults write wakes this observer; only a real change costs a re-fit.
            return
        }
        smartNames.isEnabled = showsSuggestions
        routeSuggestions.isEnabled = showsSuggestions
        scheduleAsynchronousNameResize()
    }

    /// React to the item list changing: shrink smoothly on removals, and run the
    /// open/retract logic when the empty↔non-empty state actually flips. (Growth on
    /// insertions is driven separately by the SwiftUI content's measured height — see
    /// `contentHeightDidChange`.)
    private func shelfItemsDidChange(_ items: [StoredItem]) {
        let previousCount = lastItemCount
        sizingItems = items
        smart?.itemsDidChange(items, countChanged: items.count != previousCount)
        lastItemCount = items.count
        let isEmpty = items.isEmpty
        if items.count < previousCount, !isEmpty {
            animateRemovalResize()
        } else if items.count > previousCount {
            // New content arriving cancels any in-flight removal shrink so the card can
            // grow for it right away.
            endRemovalResize()
            if dropLayoutMutationInFlight {
                dropInsertionResizePending = true
            } else {
                scheduleInsertionResize()
            }
        }
        guard isEmpty != wasEmpty else { return }
        wasEmpty = isEmpty
        shelfContentDidChange(isEmpty: isEmpty)
    }

    /// Grow smoothly from the exact fixed-row estimate whenever items are inserted.
    /// Previously insertion growth either depended solely on SwiftUI's constrained
    /// natural-height preference or snapped the panel directly to its new frame.
    ///
    /// Drops arrive in the drag event-tracking runloop mode, so perform the frame change
    /// in the default mode. While the one deliberate resize animates, measured-height
    /// callbacks are suppressed so they cannot snap the panel to an intermediate frame.
    private func scheduleInsertionResize() {
        insertionResizeGeneration &+= 1
        let generation = insertionResizeGeneration
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.insertionResizeGeneration == generation else {
                    return
                }
                self.suppressMeasuredHeightResizes()
                self.resizeToFitVisible(animated: true)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self?.hostView.clampScrollToTopIfContentFits()
                }
            }
        }
    }

    private func beginDropLayoutMutation() {
        dropLayoutMutationInFlight = true
    }

    private func endDropLayoutMutation() {
        dropLayoutMutationInFlight = false
        guard dropInsertionResizePending else { return }
        dropInsertionResizePending = false
        scheduleInsertionResize()
    }

    /// The SwiftUI content reported a new natural height — size the visible window to
    /// fit it exactly.
    private func contentHeightDidChange(_ height: CGFloat) {
        guard height > 0 else { return }
        measuredContentHeight = height
        // A drop mid-drag can leave the overflow ScrollView scrolled (see
        // clampScrollToTopIfContentFits) — heal it as soon as the content resizes.
        hostView.clampScrollToTopIfContentFits()
        // A removal already animated the window to its exact final frame; the heights
        // streaming out of the rows' shrink animation must not fight it.
        guard !removalResizeInFlight else { return }
        // Snap, don't animate: this fires when rows are added/removed, and animating the
        // frame there makes the fading row appear to slide as the card re-centers.
        //
        // Deferred to the default runloop mode: a drop landing mid-drag delivers this
        // while the drag session is tearing down (event-tracking mode), and a setFrame
        // issued there double-applies the height delta to the contentView via
        // autoresizing — shearing the card one row upward, permanently. Waiting for the
        // default mode means the window grows a few ms after the drag ends instead.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.removalResizeInFlight else { return }
                self.resizeToFitVisible(animated: false)
            }
        }
    }

    /// Row-removal resize: one smooth window animation to the exact final frame, in step
    /// with the rows' own slide (same duration + ease). The frame keeps the card's *top*
    /// edge where it is — rows above the deleted one don't move at all, the rows below
    /// slide up, and the card's bottom follows the last row — instead of re-centering,
    /// which made every remaining row shift.
    private func animateRemovalResize() {
        guard panel.isVisible, dragOutDockedFrame == nil else { return }
        let target: NSRect
        if revealMode == .free {
            removalResizeInFlight = true
            target = freePanelFrame()
        } else if let screen = Self.liveScreen(shownScreen) {
            removalResizeInFlight = true
            target = removalFrameKeepingTop(on: screen)
        } else {
            return
        }
        removalResizeTask?.cancel()
        removalResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.endRemovalResize()
        }
        windowController.resize(
            to: target,
            animated: true,
            duration: Self.removalAnimationDuration,
            timing: CAMediaTimingFunction(name: .easeOut)
        )
    }

    /// Matches the rows' removal animation in ShelfContentView (easeOut 0.18s) so the
    /// card's bottom edge and the last row arrive together.
    private static let removalAnimationDuration: CFTimeInterval = 0.18

    /// Ignore the measured heights streaming out of an in-flight SwiftUI layout
    /// animation (the bar fading in on pin, or out on lock): each tick would
    /// snap-resize the window out from under the one deliberate animated resize
    /// running alongside. While suppressed, `fittedContentHeight` sizes from the
    /// estimate — which already reflects the bar's final state — so that resize
    /// targets the exact final frame; `endRemovalResize` trues up once settled.
    private func suppressMeasuredHeightResizes() {
        removalResizeInFlight = true
        removalResizeTask?.cancel()
        removalResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.endRemovalResize()
        }
    }

    /// The rows have settled — resume measured-height-driven sizing and true-up once
    /// (a no-op when the animation landed where expected).
    private func endRemovalResize() {
        removalResizeTask?.cancel()
        removalResizeTask = nil
        guard removalResizeInFlight else { return }
        removalResizeInFlight = false
        guard panel.isVisible else {
            grabberResizeTransition = nil
            hostView.setGrabberRevealProgress(0)
            return
        }
        if let transition = grabberResizeTransition {
            hostView.setGrabberRevealProgress(transition.targetProgress)
            grabberResizeTransition = nil
            measuredContentHeight = nil
            resizeToFitVisible(keepingBottomAt: transition.bottom, animated: false)
            return
        }
        resizeToFitVisible(animated: false)
    }

    /// The docked card's post-removal frame: standard width/x for its edge, but with the
    /// current top edge preserved so the card shrinks from the bottom only. (The notch
    /// card already hangs from the top, so its standard frame is used as-is.)
    private func removalFrameKeepingTop(on screen: NSScreen) -> NSRect {
        var frame = panelFrame(for: screen, edge: shownEdge)
        guard shownEdge != .notch else { return frame }
        let visible = screen.visibleFrame
        let y = panel.frame.maxY - frame.height
        frame.origin.y = min(max(y, visible.minY + 12), visible.maxY - frame.height - 12)
        return frame
    }

    /// Re-fit the open window to the current content height + width (e.g. after the
    /// label/compact toggle changes the card's width).
    private func resizeToFitVisible(animated: Bool = true) {
        guard panel.isVisible, !dismissingFreeShelf else { return }
        // Mid drag-to-pin the card is following the cursor — don't refit it to an edge
        // frame out from under the gesture.
        if dragOutDockedFrame != nil { return }
        // Any animated frame change causes SwiftUI to emit intermediate natural-height
        // measurements as its viewport moves. An immediate resize from one of those
        // callbacks would jump the panel to the endpoint and visibly cut the animation
        // short. Size from the exact row estimate during the motion, then true-up once
        // after the content settles.
        if animated, !removalResizeInFlight {
            suppressMeasuredHeightResizes()
        }
        if revealMode == .free {
            windowController.resize(to: freePanelFrame(), animated: animated)
            return
        }
        guard let screen = Self.liveScreen(shownScreen) else { return }
        let frame = panelFrame(for: screen, edge: shownEdge)
        windowController.resize(to: frame, animated: animated)
    }

    /// Smart Names arrive independently of the item row. Let the row's short label
    /// transition finish before changing the containing window's width; doing both in
    /// the same frame made screenshot rows appear to jerk sideways.
    private func scheduleAsynchronousNameResize() {
        guard !dragActive else { return }
        asynchronousNameResizeTask?.cancel()
        asynchronousNameResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled, !self.dragActive else { return }
            self.resizeToFitVisible()
            self.asynchronousNameResizeTask = nil
        }
    }

    /// Grow or collapse the handle lane while holding both the panel's bottom edge and
    /// the body viewport fixed. `grabberRevealProgress` is updated from didResize, not a
    /// separate clock, so SwiftUI consumes exactly the height AppKit adds each frame.
    private func resizeForGrabberHover(_ hovered: Bool) {
        guard panel.isVisible, !dismissingFreeShelf else { return }
        let canShowHandle = themeStore.showsGrabHandle
            && (revealMode != .free || !freeShelfLocked)
        // Capability gates opening, never closing. A setting or lock change can revoke
        // the handle while its reveal progress is still nonzero.
        guard !hovered || canShowHandle else { return }

        let startProgress = hostView.grabberRevealProgress
        let targetProgress: CGFloat = hovered ? 1 : 0
        guard abs(startProgress - targetProgress) > 0.0001 else { return }

        measuredContentHeight = nil
        suppressMeasuredHeightResizes()
        // The estimate reads the desired hover state that ShelfHostView already flipped.
        let target: NSRect
        let bottom: CGFloat
        if revealMode == .edge, previewedDockTarget != nil,
           let screen = Self.liveScreen(shownScreen) {
            // A card already traveling into a dock must retain that canonical landing;
            // its deliberate position motion is separate from the handle/body contract.
            target = panelFrame(for: screen, edge: shownEdge)
            bottom = target.minY
        } else {
            bottom = panel.frame.minY
            target = frameToFitVisible(keepingBottomAt: bottom)
        }
        grabberResizeTransition = GrabberResizeTransition(
            startHeight: panel.frame.height,
            targetHeight: target.height,
            startProgress: startProgress,
            targetProgress: targetProgress,
            bottom: bottom
        )
        if abs(target.height - panel.frame.height) < 0.001 {
            hostView.setGrabberRevealProgress(targetProgress)
            grabberResizeTransition = nil
            return
        }
        windowController.resize(to: target, animated: true)
    }

    /// Reconcile the progress-driven handle after a capability change that does not
    /// itself generate a mouse-enter/exit event (settings, locking, or re-docking).
    private func reconcileGrabberForCurrentState() {
        let canShowHandle = themeStore.showsGrabHandle
            && (revealMode != .free || !freeShelfLocked)
        let shouldShow = hostView.isCardHovered && canShowHandle
        measuredContentHeight = nil
        let targetProgress: CGFloat = shouldShow ? 1 : 0
        if abs(hostView.grabberRevealProgress - targetProgress) > 0.0001 {
            resizeForGrabberHover(shouldShow)
        } else {
            resizeToFitVisible()
        }
    }

    /// Map the panel's current animation height onto the handle-lane reveal. Because
    /// both share the same fraction, the body below remains exactly the same height.
    private func syncGrabberRevealToLivePanelSize() {
        guard let transition = grabberResizeTransition else { return }
        let heightDelta = transition.targetHeight - transition.startHeight
        guard abs(heightDelta) > 0.001 else {
            hostView.setGrabberRevealProgress(transition.targetProgress)
            return
        }
        let fraction = min(max((panel.frame.height - transition.startHeight) / heightDelta, 0), 1)
        let progress = transition.startProgress
            + (transition.targetProgress - transition.startProgress) * fraction
        hostView.setGrabberRevealProgress(progress)
    }

    private func frameToFitVisible(keepingBottomAt bottom: CGFloat) -> NSRect {
        if revealMode == .free {
            var target = freePanelFrame()
            target.origin.y = bottom
            target = Self.clampedOnScreen(target, on: Self.screenForFrame(target))
            freeTopLeft = NSPoint(x: target.minX, y: target.maxY)
            return target
        }
        guard let screen = Self.liveScreen(shownScreen) else { return panel.frame }
        var target = panelFrame(for: screen, edge: shownEdge)
        target.origin.y = bottom
        return Self.clampedOnScreen(target, on: screen)
    }

    /// Keep a frame whose vertical position was pinned — to a held bottom edge, rather
    /// than recomputed — fully on its screen.
    ///
    /// Holding the bottom while the card grows is deliberate (the body viewport must not
    /// jump as the handle lane opens), but on its own it lets a tall card push its top
    /// edge past the menu bar, which is how the first rows ended up off-screen. Clamping
    /// afterwards keeps the contract for every size that fits and gives up the pin only
    /// when honoring it would put content where it cannot be seen. Mirrors the clamp in
    /// `removalFrameKeepingTop`.
    private static func clampedOnScreen(_ frame: NSRect, on screen: NSScreen?) -> NSRect {
        guard let screen else { return frame }
        let visible = screen.visibleFrame
        var result = frame
        result.size.height = min(result.height, visible.height - 24)
        let lowerBound = visible.minY + 12
        let upperBound = visible.maxY - result.height - 12
        result.origin.y = min(max(result.minY, lowerBound), max(lowerBound, upperBound))
        return result
    }

    /// The screen a free-floating card is mostly on, so it is clamped against the display
    /// it actually occupies rather than whichever one the shelf last docked to.
    private static func screenForFrame(_ frame: NSRect) -> NSScreen? {
        let overlap: (NSScreen) -> CGFloat = {
            let r = $0.frame.intersection(frame)
            return r.isNull ? 0 : r.width * r.height
        }
        return NSScreen.screens.max { overlap($0) < overlap($1) } ?? NSScreen.main
    }

    private func resizeToFitVisible(keepingBottomAt bottom: CGFloat, animated: Bool) {
        guard panel.isVisible, !dismissingFreeShelf else { return }
        windowController.resize(to: frameToFitVisible(keepingBottomAt: bottom), animated: animated)
    }

    private func setTabsShown(_ shown: Bool) {
        let shown = shown && themeStore.showsEdgeTab
        for strip in edgeStrips {
            strip.showsTab = shown
        }
    }

    private func setDragActive(_ active: Bool) {
        dragActive = active
        // A retract scheduled just before the drag pasteboard became active must not
        // win the next main-loop turn and hide the drop target mid-gesture.
        if active {
            cancelRetract()
        }
        // Ghost rows hide for the drag's duration so the drop geometry never shifts
        // under the cursor.
        setArrivalsSuppressed(active)
        hostView.setDropTarget(active)
        // The drag ended somewhere off the shelf; make sure the outline is cleared even
        // if no draggingExited arrived.
        if !active {
            hostView.setDragOverShelf(false)
        }
        // Keep the panel frame fixed for the whole gesture. In particular, hiding
        // recent-arrival rows must not stack a resize onto the reveal animation.
        // `dragDidEnd` performs one reconciled resize after the visibility hold ends.
    }

    /// Hide (or restore) the ghost rows for a drag. Offers left over from a reveal the
    /// user ignored are still in the model when the shelf retracts, so a drag that
    /// re-reveals the shelf is sized while they are on their way out: the last measured
    /// height still counts them, and it *wins* over the estimate in `fittedContentHeight`
    /// because it is the larger of the two — the card would open at the ghosts' height
    /// and then snap down mid-reveal. Drop the measurement whenever suppression actually
    /// changes what is on the shelf. (The rows themselves leave without animating; see
    /// ShelfContentView's ghost animation.)
    private func setArrivalsSuppressed(_ suppressed: Bool) {
        let changesGhostVisibility = arrivals.suppressed != suppressed
            && !arrivals.visibleGhosts.isEmpty
        if changesGhostVisibility || store.items.isEmpty {
            measuredContentHeight = nil
        }
        arrivals.suppressed = suppressed
    }

    /// Show only the tab belonging to the shelf's established dock. The pointer may
    /// begin a drag anywhere on the desktop; it does not get to relocate the shelf.
    private func showHomeTab() {
        guard usesEdgeDock, themeStore.showsEdgeTab else {
            setTabsShown(false)
            return
        }
        guard let home = homeStrip() else { return }
        for strip in edgeStrips {
            strip.showsTab = (strip === home)
        }
    }

    private func homeStrip() -> EdgeStripWindow? {
        let targetEdge = panel.isVisible ? shownEdge : preferredEdge
        let targetScreen = panel.isVisible ? shownScreen : preferredScreen
        let matchingEdge = edgeStrips.filter { $0.edge == targetEdge }
        if let targetScreen,
           let exact = matchingEdge.first(where: {
               $0.pinnedScreen == targetScreen
           }) {
            return exact
        }
        return matchingEdge.min(by: {
            Self.distance(from: panel.frame.origin, to: $0.frame)
                < Self.distance(from: panel.frame.origin, to: $1.frame)
        }) ?? resolvedPreferredStrip()
    }

    /// The enabled edge tab whose catch zone is nearest the cursor.
    private func nearestStrip(to point: NSPoint) -> EdgeStripWindow? {
        edgeStrips.min(by: {
            Self.distance(from: point, to: $0.frame) < Self.distance(from: point, to: $1.frame)
        })
    }

    /// "Reveal while dragging": open at the shelf's existing/home dock. Only flagged as
    /// drag-revealed if it wasn't already open, so a persistent full shelf is untouched.
    private func revealForDrag() {
        guard usesEdgeDock else { return }
        if !panel.isVisible { revealedForDrag = true }
        if let shownScreen, edgeSettings.isEnabled(shownEdge) {
            preferredScreen = shownScreen
            preferredEdge = shownEdge
        }
        revealIfNeeded()
    }

    /// End of a drag: release the global visibility hold, rebuild pointer ownership
    /// from the real cursor, and only then allow an empty edge shelf to retract.
    private func dragDidEnd() {
        revealedForDrag = false
        guard panel.isVisible else { return }
        guard revealMode == .edge else {
            resizeToFitVisible()
            return
        }

        let pointerIsOverShelf = pointerOverShelfOrTab(NSEvent.mouseLocation)
        pointerInRegion = pointerIsOverShelf
        guard shouldAutomaticallyRetractEmptyShelf(
            pointerInKeepAliveRegion: pointerIsOverShelf
        ) else {
            resizeToFitVisible()
            return
        }
        hostView.resetInteraction()
        windowController.hide(animated: true)
    }

    // MARK: Cursor summon (free-floating shelf)

    /// Shake-to-summon: bring the shelf to the cursor as a free-floating, movable card.
    /// Works whether the shelf is currently hidden or already docked at an edge. A
    /// locked free shelf is a fixture — the summon must not yank it from its spot.
    private func summonAtCursor(_ point: NSPoint) {
        if revealMode == .free, freeShelfLocked, panel.isVisible { return }
        detachFromSystemDock(makeVisible: false)
        // A deliberate summon adopts any preview shelf (the settings closure re-flags).
        shelfIsSettingsPreview = false
        // A summon within the dismissal fade must lift the resize hold, or the fresh
        // shelf keeps its stale size until the old dismissal's timer clears the flag.
        dismissingFreeShelfResetTask?.cancel()
        dismissingFreeShelfResetTask = nil
        dismissingFreeShelf = false
        if !panel.isVisible {
            refreshArrivals(markRevealed: true)
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main ?? NSScreen.screens.first
        summonScreen = screen
        revealMode = .free
        freeSourceEdge = .right
        revealedForDrag = false
        setTabsShown(false)
        hostView.setFreeMode(true)
        // Don't let an in-flight edge retract pull the freshly summoned shelf away.
        cancelOpen()
        cancelRetract()
        stopRetractWatcher()
        pointerInRegion = false

        // Anchor the card just down-right of the cursor (menu-like), then clamp on-screen.
        freeTopLeft = NSPoint(x: point.x - 24, y: point.y + 12)
        let frame = freePanelFrame()
        freeTopLeft = NSPoint(x: frame.minX, y: frame.maxY)

        if panel.isVisible {
            // Docked → free: the bar may be fading in as the card flies to the cursor;
            // same snap-suppression as pinning.
            suppressMeasuredHeightResizes()
            windowController.usesFreeAnimation = true
            windowController.resize(to: frame)
        } else {
            windowController.revealFromCursor(animated: true, targetFrame: frame)
        }
    }

    /// The free-floating card frame: sized exactly like the docked card (same width
    /// rules, same content-hugging height, same empty strip), positioned at
    /// `freeTopLeft` clamped fully onto its screen.
    private func freePanelFrame() -> NSRect {
        let screen = Self.liveScreen(summonScreen)
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let width = min(cardWidth(for: freeSourceEdge), visible.width - 16)
        let usable = visible.height - 24
        let height = min(
            usesSquareStack ? width : max(fittedContentHeight(), themeStore.heightFraction * usable),
            usable
        )
        let size = NSSize(width: width, height: height)

        if let dockAttachment,
           let attached = systemDockFrames(for: size, followsVisibility: true)
            .first(where: { $0.kind == dockAttachment }) {
            return attached.frame
        }

        let anchor = freeTopLeft ?? NSPoint(x: visible.midX - width / 2, y: visible.midY + height / 2)
        let x = min(max(anchor.x, visible.minX + 8), visible.maxX - width - 8)
        // freeTopLeft is the top edge; convert to a bottom-left origin and clamp.
        // The floor is the *screen* edge, not the visible frame: a hand-placed card
        // may sit level with the Dock, beside it (overlapping the Dock itself just
        // puts the card behind it — still the user's call). The ceiling keeps the
        // visible frame so the card never slides under the menu bar.
        let y = min(max(anchor.y - height, Self.freeBottomFloor(screen: screen, visible: visible)),
                    visible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// The lowest y a free card may occupy: 8pt above the true screen bottom, so
    /// "next to the Dock, at its level" is a valid parking spot. Shared by
    /// `freePanelFrame` and the lock re-fit so they can never disagree.
    private static func freeBottomFloor(screen: NSScreen?, visible: NSRect) -> CGFloat {
        (screen?.frame.minY ?? visible.minY) + 8
    }

    /// Remember the user's chosen position after they drag the free shelf by its handle.
    private func captureFreeOrigin() {
        guard revealMode == .free, dockAttachment == nil, panel.isVisible else { return }
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: Drag-to-pin (tear the docked card off its edge)

    /// How close the center of a free shelf must be to its canonical docked position
    /// when released for it to snap home. Center distance works consistently for side
    /// and notch docks, including when their widths differ.
    private static let dockSnapDistance: CGFloat = 120
    /// Once the outline is visible, a small release buffer prevents tiny pointer
    /// movements around the threshold from flickering it on and off.
    private static let dockPreviewExitDistance: CGFloat = 145

    private enum DockSnapTargetKind: Equatable {
        case edge(ShelfEdge)
        case dockLeading
        case dockTrailing
    }

    private struct DockSnapTarget {
        let screen: NSScreen
        let kind: DockSnapTargetKind
        let frame: NSRect
        let distance: CGFloat
    }

    /// How far the card must travel from its docked frame to detach; released closer
    /// than this it snaps back to the edge and stays docked.
    private static let pinDetachDistance: CGFloat = 40

    /// Mouse-up on a drag-to-pin gesture: far enough from the docked frame, the card
    /// pins where it was dropped as a free-floating shelf (the same persistence as
    /// shake-to-summon); otherwise it snaps back to its edge. A shelf that was already
    /// free also gets a chance to re-dock at any enabled edge.
    private func shelfDragDidEnd() {
        if revealMode == .free {
            guard snapBackToEdgesEnabled else {
                clearDockSnapPreview()
                return
            }
            let target = refreshedPreviewedDockTarget() ?? nearestDockSnapTarget()
            if let target {
                snapFreeShelf(to: target)
            } else {
                clearDockSnapPreview()
            }
            return
        }
        clearDockSnapPreview()
        guard let docked = dragOutDockedFrame else { return }
        dragOutDockedFrame = nil
        let moved = hypot(panel.frame.minX - docked.minX, panel.frame.minY - docked.minY)
        if moved >= Self.pinDetachDistance {
            pinShelfAtCurrentPosition()
        } else {
            windowController.resize(to: docked)
        }
    }

    /// The closest enabled, physically reachable dock whose resting frame is near the
    /// free card. `edgeStrips` already excludes disabled edges, notch docks on screens
    /// without a notch, and side edges that are internal seams between displays.
    private func nearestDockSnapTarget() -> DockSnapTarget? {
        availableDockSnapTargets()
            .filter { $0.distance <= Self.dockSnapDistance }
            .min { $0.distance < $1.distance }
    }

    private func availableDockSnapTargets() -> [DockSnapTarget] {
        let edgeTargets = edgeStrips.map { strip -> DockSnapTarget in
            let frame = panelFrame(for: strip.pinnedScreen, edge: strip.edge)
            let distance = hypot(panel.frame.midX - frame.midX, panel.frame.midY - frame.midY)
            return DockSnapTarget(
                screen: strip.pinnedScreen,
                kind: .edge(strip.edge),
                frame: frame,
                distance: distance
            )
        }
        return edgeTargets + dockAdjacentSnapTargets()
    }

    /// Two live targets at the Dock's ends. Horizontal Docks get left/right targets;
    /// vertical Docks get below/above targets. Geometry comes from Accessibility so the
    /// positions follow the actual item-dependent Dock length instead of an estimate.
    private func dockAdjacentSnapTargets() -> [DockSnapTarget] {
        systemDockFrames(for: panel.frame.size, followsVisibility: false).map { placement in
            DockSnapTarget(
                screen: placement.screen,
                kind: placement.kind,
                frame: placement.frame,
                distance: hypot(
                    panel.frame.midX - placement.frame.midX,
                    panel.frame.midY - placement.frame.midY
                )
            )
        }
    }

    private struct SystemDockPlacement {
        let screen: NSScreen
        let kind: DockSnapTargetKind
        let frame: NSRect
    }

    /// Frames beside the Dock at its fully shown position, or translated off-screen by
    /// the Dock's current auto-hide progress. The card travels its own full dimension
    /// while the smaller Dock travels its full thickness, so both disappear together.
    private func systemDockFrames(
        for size: NSSize,
        followsVisibility: Bool,
        requireFeatureEnabled: Bool = true
    ) -> [SystemDockPlacement] {
        guard let dock = DockGeometryReader.currentGeometry(
            useCache: !followsVisibility,
            requireFeatureEnabled: requireFeatureEnabled
        ) else { return [] }
        let gap: CGFloat = 12
        let inset: CGFloat = 8
        let screen = dock.screen.frame
        let shownCandidates: [(DockSnapTargetKind, NSPoint)]
        let visibility: CGFloat

        switch dock.orientation {
        case .horizontal:
            let y = screen.minY + inset
            shownCandidates = [
                (.dockLeading, NSPoint(x: dock.frame.minX - gap - size.width, y: y)),
                (.dockTrailing, NSPoint(x: dock.frame.maxX + gap, y: y))
            ]
            let hiddenTop = screen.minY + 4
            visibility = min(max(
                (dock.frame.maxY - hiddenTop) / max(1, dock.frame.height + 4),
                0
            ), 1)
        case .vertical:
            let dockIsLeft = dock.frame.midX < screen.midX
            let x = dockIsLeft
                ? dock.frame.maxX + gap
                : dock.frame.minX - gap - size.width
            shownCandidates = [
                (.dockLeading, NSPoint(x: x, y: dock.frame.minY - gap - size.height)),
                (.dockTrailing, NSPoint(x: x, y: dock.frame.maxY + gap))
            ]
            let visibleThickness = dockIsLeft
                ? dock.frame.maxX - (screen.minX + 4)
                : (screen.maxX - 4) - dock.frame.minX
            visibility = min(max(visibleThickness / max(1, dock.frame.width + 4), 0), 1)
        }

        return shownCandidates.compactMap { kind, shownOrigin in
            let shownFrame = NSRect(origin: shownOrigin, size: size)
            guard shownFrame.minX >= screen.minX + inset,
                  shownFrame.maxX <= screen.maxX - inset,
                  shownFrame.minY >= screen.minY + inset,
                  shownFrame.maxY <= screen.maxY - inset
            else { return nil }

            var liveOrigin = shownOrigin
            if followsVisibility {
                switch dock.orientation {
                case .horizontal:
                    let hiddenY = screen.minY - size.height
                    liveOrigin.y = hiddenY + (shownOrigin.y - hiddenY) * visibility
                case .vertical:
                    let dockIsLeft = dock.frame.midX < screen.midX
                    let hiddenX = dockIsLeft ? screen.minX - size.width : screen.maxX
                    liveOrigin.x = hiddenX + (shownOrigin.x - hiddenX) * visibility
                }
            }
            return SystemDockPlacement(
                screen: dock.screen,
                kind: kind,
                frame: NSRect(origin: liveOrigin, size: size)
            )
        }
    }

    /// Recompute the latched preview target using the slightly wider exit radius. This
    /// keeps the indicator and release behavior in agreement throughout the buffer.
    private func refreshedPreviewedDockTarget() -> DockSnapTarget? {
        guard let previewedDockTarget,
              let refreshed = availableDockSnapTargets().first(where: {
                  $0.screen == previewedDockTarget.screen && $0.kind == previewedDockTarget.kind
              }),
              refreshed.distance <= Self.dockPreviewExitDistance
        else { return nil }
        return refreshed
    }

    /// Reveal the exact landing frame while a free shelf is inside the snap radius.
    /// Moving away or dragging a still-docked shelf removes the preview immediately.
    private func updateDockSnapPreview() {
        guard revealMode == .free, snapBackToEdgesEnabled else {
            clearDockSnapPreview()
            return
        }
        let target = refreshedPreviewedDockTarget() ?? nearestDockSnapTarget()
        guard let target else {
            clearDockSnapPreview()
            return
        }
        dockSnapPreviewHideTask?.cancel()
        dockSnapPreviewHideTask = nil
        previewedDockTarget = target
        dockSnapPreview.show(
            at: target.frame,
            cornerRadius: themeStore.theme.cardCornerRadius,
            toward: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        )
    }

    /// Match the preview to the real panel's presentation size on every AppKit resize
    /// tick. Only its origin is recomputed for the dock anchor, so width and height are
    /// never approximated by a second independent animation.
    private func syncDockPreviewToLivePanelSize() {
        guard revealMode == .edge,
              let previewedDockTarget,
              case let .edge(edge) = previewedDockTarget.kind
        else { return }
        let frame = Self.panelFrame(
            for: previewedDockTarget.screen,
            edge: edge,
            contentHeight: panel.frame.height,
            width: panel.frame.width,
            centerY: nil
        )
        self.previewedDockTarget = DockSnapTarget(
            screen: previewedDockTarget.screen,
            kind: previewedDockTarget.kind,
            frame: frame,
            distance: previewedDockTarget.distance
        )
        dockSnapPreview.show(
            at: frame,
            cornerRadius: themeStore.theme.cardCornerRadius,
            toward: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        )
    }

    private func clearDockSnapPreview() {
        dockSnapPreviewHideTask?.cancel()
        dockSnapPreviewHideTask = nil
        previewedDockTarget = nil
        dockSnapPreview.hide()
    }

    /// Animate a free shelf into an enabled dock and restore the ordinary edge lifecycle:
    /// enabled tab behavior, empty-shelf auto-retraction, and future edge reveals.
    private func snapFreeShelf(to target: DockSnapTarget) {
        if case .dockLeading = target.kind {
            snapFreeShelfBesideDock(to: target)
            return
        }
        if case .dockTrailing = target.kind {
            snapFreeShelfBesideDock(to: target)
            return
        }
        guard case let .edge(edge) = target.kind else { return }
        clearSystemDockAttachment()

        // Keep the destination ghost in place while the real card travels toward it,
        // then remove it just before the card finishes covering the target.
        previewedDockTarget = target
        dockSnapPreviewHideTask?.cancel()
        dockSnapPreviewHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.dockSnapPreview.hide()
            self?.previewedDockTarget = nil
            self?.dockSnapPreviewHideTask = nil
        }
        shelfIsSettingsPreview = false
        revealMode = .edge
        freeShelfLocked = false
        freeTopLeft = nil
        summonScreen = nil
        freeSourceEdge = edge
        preferredScreen = target.screen
        shownScreen = target.screen
        preferredEdge = edge
        shownEdge = edge
        persistPreferredEdge()
        revealedForDrag = false
        dragOutDockedFrame = nil
        pointerInRegion = false
        hostView.setLockedInPlace(false)
        hostView.setFreeMode(false)
        setTabsShown(false)
        cancelOpen()
        cancelRetract()
        stopRetractWatcher()
        windowController.usesFreeAnimation = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Establish the dock anchor with the card's exact starting size before AppKit
        // begins streaming the remaining animation frames through didResize.
        syncDockPreviewToLivePanelSize()
        windowController.resize(
            to: target.frame,
            animated: true,
            duration: 0.36,
            timing: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        )
        // Let an empty card visibly finish landing before normal pointer-out behavior
        // gets a chance to retract it back to its tab.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard let self,
                  self.panel.isVisible,
                  self.revealMode == .edge,
                  self.shownScreen == target.screen,
                  self.shownEdge == edge else { return }
            self.reconcileGrabberForCurrentState()
            self.startRetractWatcher()
        }
        NSLog("Perch snapped free shelf to \(edge.rawValue) edge")
    }

    /// Land at one end of the live system Dock and adopt its visibility lifecycle.
    /// Perch remains a free-layout card, but its origin follows the Dock until the user
    /// grabs it again or snaps it to a screen edge.
    private func snapFreeShelfBesideDock(to target: DockSnapTarget) {
        previewedDockTarget = target
        dockSnapPreviewHideTask?.cancel()
        dockSnapPreviewHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.dockSnapPreview.hide()
            self?.previewedDockTarget = nil
            self?.dockSnapPreviewHideTask = nil
        }
        shelfIsSettingsPreview = false
        freeShelfLocked = false
        summonScreen = target.screen
        freeTopLeft = nil
        dockAttachment = target.kind
        hostView.setLockedInPlace(false)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        windowController.usesFreeAnimation = true
        windowController.resize(
            to: target.frame,
            animated: true,
            duration: 0.36,
            timing: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        )
        startSystemDockTracking()
        NSLog("Perch snapped free shelf beside the Dock")
    }

    /// Fast enough to ride the Dock's auto-hide animation frame for frame.
    private static let dockTrackingActiveInterval: Duration = .milliseconds(16)
    /// A Dock the cursor is nowhere near cannot start animating, so it can be sampled
    /// far more cheaply — each sample is a synchronous cross-process Accessibility read
    /// on the main actor.
    private static let dockTrackingIdleInterval: Duration = .milliseconds(200)
    /// Keep sampling fast for a beat after the last movement so the tail of an
    /// animation is never truncated by an early back-off.
    private static let dockTrackingCoastTicks = 40
    /// How close the cursor must come to the Dock's shown position to re-arm fast
    /// sampling — generous, because the reveal begins before the pointer lands.
    private static let dockTrackingWakeDistance: CGFloat = 260

    private func startSystemDockTracking() {
        dockTrackingTask?.cancel()
        guard let attachment = dockAttachment else { return }
        dockTrackingTask = Task { @MainActor [weak self] in
            var lastOrigin: NSPoint?
            var coastingTicks = 0
            while !Task.isCancelled {
                guard let self, self.dockAttachment == attachment else { return }
                if !UserDefaults.standard.bool(forKey: PerchSettings.snapBesideDock) {
                    self.detachFromSystemDock(makeVisible: true)
                    return
                }
                if let placement = self.systemDockFrames(
                    for: self.panel.frame.size,
                    followsVisibility: true
                ).first(where: { $0.kind == attachment }) {
                    if placement.frame.origin != lastOrigin {
                        lastOrigin = placement.frame.origin
                        coastingTicks = Self.dockTrackingCoastTicks
                        // Direct origin updates preserve the Dock's live timing instead
                        // of layering a second AppKit animation on top of it.
                        self.panel.setFrameOrigin(placement.frame.origin)
                    } else if coastingTicks > 0 {
                        coastingTicks -= 1
                    }
                }
                try? await Task.sleep(
                    for: coastingTicks > 0 || self.cursorCouldWakeSystemDock(attachment)
                        ? Self.dockTrackingActiveInterval
                        : Self.dockTrackingIdleInterval
                )
            }
        }
    }

    /// Whether the cursor is near enough to the Dock's *shown* frame to trigger a
    /// reveal. The shown frame — not the panel's current position — is the anchor: a
    /// hidden Dock has carried the panel off-screen, and the cursor approaching the
    /// screen edge is exactly the moment fast sampling has to resume.
    private func cursorCouldWakeSystemDock(_ attachment: DockSnapTargetKind) -> Bool {
        // Reads through DockGeometryReader's short cache, which the live sample above
        // has just refreshed — no extra Accessibility round trip.
        guard let shown = systemDockFrames(
            for: panel.frame.size,
            followsVisibility: false
        ).first(where: { $0.kind == attachment })?.frame else {
            return true
        }
        return Self.distance(from: NSEvent.mouseLocation, to: shown)
            <= Self.dockTrackingWakeDistance
    }

    /// Stop following the Dock. A user-initiated drag keeps the current presentation
    /// position; disabling the feature restores the fully shown adjacent position.
    private func detachFromSystemDock(makeVisible: Bool) {
        guard let attachment = dockAttachment else { return }
        if makeVisible,
           let placement = systemDockFrames(
            for: panel.frame.size,
            followsVisibility: false,
            requireFeatureEnabled: false
           )
            .first(where: { $0.kind == attachment }) {
            panel.setFrameOrigin(placement.frame.origin)
        }
        clearSystemDockAttachment()
        summonScreen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? summonScreen
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    private func clearSystemDockAttachment() {
        dockAttachment = nil
        dockTrackingTask?.cancel()
        dockTrackingTask = nil
    }

    /// Convert the dragged-out card into a free-floating shelf pinned at its current
    /// position — the drag-out twin of `summonAtCursor`.
    private func pinShelfAtCurrentPosition() {
        clearSystemDockAttachment()
        summonScreen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main ?? NSScreen.screens.first
        revealMode = .free
        freeSourceEdge = shownEdge
        revealedForDrag = false
        setTabsShown(false)
        hostView.setFreeMode(true)
        cancelOpen()
        cancelRetract()
        stopRetractWatcher()
        pointerInRegion = false
        // Keep the card's top-left where the user dropped it; the free frame grows
        // downward from there and clamps on-screen.
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        // The bar stays in the layout under the pointer as the card pins; its height
        // ticks must not snap-resize the window mid-pin.
        suppressMeasuredHeightResizes()
        windowController.usesFreeAnimation = true
        windowController.resize(to: freePanelFrame())
    }

    /// Toggle "Lock Position" on the free shelf. Reconcile through the same live
    /// progress path as hover so locking while the bar is visible retracts only the
    /// top lane while the body and bottom edge remain stationary.
    private func toggleFreeShelfLock() {
        guard revealMode == .free else { return }
        freeShelfLocked.toggle()
        if freeShelfLocked { shelfIsSettingsPreview = false }
        hostView.setLockedInPlace(freeShelfLocked)
        reconcileGrabberForCurrentState()
    }

    /// Clear away a shelf that exists only as the settings Appearance preview (the tab
    /// was deselected or the window closed). A shelf the user adopted — locked, put
    /// items on, or that was already on screen before the preview — stays put.
    private func clearSettingsPreviewShelf() {
        guard shelfIsSettingsPreview else { return }
        shelfIsSettingsPreview = false
        guard revealMode == .free, !freeShelfLocked, store.items.isEmpty else { return }
        dismissFreeShelf()
    }

    /// Tear down the free-floating shelf (✕ pressed, or it emptied out) and return to
    /// edge-docked behavior. Items, if any, stay in the store. Closing also releases
    /// the position lock — the next free shelf starts movable.
    private func dismissFreeShelf() {
        dismissingFreeShelf = true
        clearSystemDockAttachment()
        clearDockSnapPreview()
        revealMode = .edge
        freeShelfLocked = false
        shelfIsSettingsPreview = false
        hostView.setLockedInPlace(false)
        freeTopLeft = nil
        summonScreen = nil
        pointerInRegion = false
        stopRetractWatcher()
        cancelRetract()
        hostView.resetInteraction()
        windowController.hide(animated: true)
        // The host's free-mode behaviors are reset when the shelf next docks at an edge.
        windowController.usesFreeAnimation = false
        dismissingFreeShelfResetTask?.cancel()
        dismissingFreeShelfResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.dismissingFreeShelf = false
        }
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: ShelfDropHandling

    func handleDrop(_ pasteboard: NSPasteboard, fromPerch: Bool) -> Bool {
        // Dropping an in-flight Perch drag back onto Perch means "put these back."
        // The originals are still in the store (only visually hidden), so accepting
        // without snapshotting preserves every selected row and avoids round-tripping
        // our own concrete URLs + file promises into one compound replacement item.
        if fromPerch {
            cancelOpen()
            cancelRetract()
            NSLog("Perch internal drag returned to shelf")
            return true
        }

        let beforeCount = store.items.count
        let batchID = UUID()
        let droppedAt = Date()
        let sourceApplication = SourceApplicationCapture.current()

        do {
            beginDropLayoutMutation()
            defer { endDropLayoutMutation() }

            let results = try snapshotter.snapshot(pasteboard, into: store)
            for result in results {
                registerScreenshotPresentationIfNeeded(for: result.item)
            }
            let movedSourcePaths = results.flatMap { result -> [String] in
                guard let origins = result.item.metadata.originPaths else {
                    return []
                }
                return Array(origins.values)
            }
            arrivals.excludePermanently(movedSourcePaths)

            let afterCount = store.items.count
            let backingFiles = results.flatMap { $0.item.backingFileURLs() }.map(\.lastPathComponent).joined(separator: ",")

            NSLog(
                "Perch drop stored \(results.count) item(s); count \(beforeCount)->\(afterCount); files [\(backingFiles)]"
            )

            for result in results {
                let recordingContext = DropRecordingContext(
                    batchID: batchID,
                    occurredAt: droppedAt,
                    sourceApplication: sourceApplication
                )
                finalizeDrop(
                    result,
                    initialCount: beforeCount,
                    recordingContext: recordingContext
                )
            }

            // Keep the shelf open after a drop (the pointer is over it); it closes
            // when the pointer leaves.
            cancelOpen()
            cancelRetract()
            return true
        } catch {
            NSLog("Perch drop failed: \(error)")
            return false
        }
    }

    func pointerDidEnterShelf() {
        // Pointer (hover or drag) is inside the panel — keep it open.
        enterRegion(immediate: true)
    }

    func pointerDidExitShelf(duringDrag: Bool) {
        exitRegion(duringDrag: duringDrag)
    }

    func dragOverShelfDidChange(_ over: Bool) {
        hostView.setDragOverShelf(over)
    }

    // MARK: EdgeStripDelegate

    func edgeStrip(_ strip: EdgeStripWindow, pointerDidEnterViaDrag viaDrag: Bool) {
        guard usesEdgeDock else {
            setTabsShown(false)
            return
        }
        if viaDrag {
            // Hidden edge windows still receive AppKit drag-entry events even when
            // their tab is not drawn. Ignore every dock except the one we deliberately
            // advertised, or crossing the desktop can teleport the live shelf.
            guard homeStrip() === strip else { return }
            enterRegion(immediate: true)
            return
        }

        // A deliberate ordinary hover selects this as the shelf's future home.
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        persistPreferredEdge()
        enterRegion(immediate: false)
    }

    func edgeStripPointerDidExit(_ strip: EdgeStripWindow, duringDrag: Bool) {
        guard usesEdgeDock else { return }
        exitRegion(duringDrag: duringDrag)
    }

    /// Height of the empty drop target — also the card's minimum size.
    private static let emptyStateHeight: CGFloat = 64
    /// The empty shelf no longer grows while a drag is in flight (it drowned out the
    /// row's landing thunk), so this matches the resting empty-state height.
    private static let dropTargetHeight: CGFloat = 64

    private static func initialPanelFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 300, height: emptyStateHeight)
        }
        return panelFrame(for: screen, edge: .right, contentHeight: emptyStateHeight, width: 300, centerY: nil)
    }

    /// The card height that hugs every rendered row: stored items plus recent-arrival
    /// ghosts. Counting only stored items lets a ghost adoption briefly floor the panel
    /// at one row, trapping the remaining ghosts inside a constrained ScrollView.
    private func contentHeight(for itemCount: Int) -> CGFloat {
        // This is the desired final height; live intermediate geometry comes from
        // `grabberRevealProgress` synchronized with the window animation.
        let showsGrabber = hostView.isCardHovered
            && themeStore.showsGrabHandle
            && (revealMode != .free || !freeShelfLocked)
        let ghostCount = arrivals.suppressed ? 0 : arrivals.visibleGhosts.count
        let rowCount = itemCount + ghostCount
        guard rowCount > 0 else {
            return (dragActive ? Self.dropTargetHeight : Self.emptyStateHeight)
                + (showsGrabber ? RowMetrics.grabberZoneHeight : 0)
        }
        let theme = themeStore.theme
        let grabber = showsGrabber ? RowMetrics.grabberZoneHeight : 0
        if themeStore.stacksItems {
            return theme.contentPadding * 2 + grabber + theme.rowHeight
        }
        let rows = CGFloat(rowCount) * theme.rowHeight
            + CGFloat(rowCount - 1) * theme.rowSpacing
        return theme.contentPadding * 2 + grabber + rows
    }

    /// The content-hugging card frame on a screen + edge. Prefers the actual measured
    /// SwiftUI height; falls back to a per-item estimate before the first measurement.
    private func panelFrame(for screen: NSScreen, edge: ShelfEdge) -> NSRect {
        let width = cardWidth(for: edge)
        return Self.panelFrame(
            for: screen,
            edge: edge,
            contentHeight: usesSquareStack ? width : flooredContentHeight(on: screen, edge: edge),
            width: width,
            centerY: nil
        )
    }

    /// The Square size becomes a true square deck when stacking is on. The other sizes
    /// stack as well; they simply keep their own proportions rather than being forced
    /// to a square.
    private var usesSquareStack: Bool {
        themeStore.stacksItems && themeStore.sizePreset == .square
    }

    /// The content height with the user's Height slider applied: a floor at that
    /// fraction of the screen's usable height, so the card can be made taller than its
    /// contents — the extra space is all drop target. Zero floors nothing (hug content).
    /// Uses the same usable-height bounds as `panelFrame`, so the floor and the cap agree.
    private func flooredContentHeight(on screen: NSScreen, edge: ShelfEdge) -> CGFloat {
        let usable = screen.visibleFrame.height - (edge == .notch ? 40 : 24)
        return max(fittedContentHeight(), themeStore.heightFraction * usable)
    }

    /// The content height the card should hug: the measured SwiftUI height, floored at
    /// the per-item estimate. Rows are fixed-height so the estimate is exact — the floor
    /// keeps a stale or mid-transition measurement from ever shrinking the card below
    /// what the current item count needs. During a removal animation the measurement is
    /// mid-shrink (still *above* the estimate), so the estimate alone is the target.
    ///
    /// Counts from `lastItemCount`, not `store.items`: `@Published` emits on willSet, so
    /// while the items sink is running `store.items` still holds the *old* list — sizing
    /// from it would target the pre-removal height and the shrink would never move.
    private func fittedContentHeight() -> CGFloat {
        let estimate = contentHeight(for: lastItemCount)
        if removalResizeInFlight { return estimate }
        return max(measuredContentHeight ?? estimate, estimate)
    }

    /// The card's width on a given edge. Empty (and icons-only) it stays a compact strip.
    /// Named item rows hug the widest visible title; the Width setting is their ceiling
    /// rather than a fixed amount of empty card.
    private func cardWidth(for edge: ShelfEdge) -> CGFloat {
        let showsGhosts = !arrivals.suppressed && !arrivals.visibleGhosts.isEmpty
        if sizingItems.isEmpty && !showsGhosts {
            return Self.emptyCardWidth * themeStore.widthScale
        }
        guard themeStore.showsLabels else { return compactCardWidth * themeStore.widthScale }

        let maximumListWidth = (edge == .notch ? 360 : 300)
            * themeStore.widthScale
        let theme = themeStore.theme
        var usesStabilizedNameWidth = false
        let itemRows = sizingItems.compactMap { item
            -> (title: String, showsAction: Bool, showsRouteAction: Bool)? in
            let name = smartNames.presentation(
                for: item.id,
                originalTitle: item.metadata.title
            )
            if name.usesStableWidth {
                usesStabilizedNameWidth = true
                return nil
            }
            return (
                title: name.title,
                showsAction: theme.showsDeleteButton,
                showsRouteAction: routeSuggestions.suggestion(for: item.id) != nil
            )
        }
        let ghostRows = showsGhosts ? arrivals.visibleGhosts.compactMap {
            ghost -> (title: String, showsAction: Bool, showsRouteAction: Bool)? in
            if smartNames.isEnabled, ghost.offer?.usesStableScreenshotName == true {
                usesStabilizedNameWidth = true
                return nil
            }
            return (
                title: ghost.displayTitle(
                    smartName: smartNames.isEnabled
                        ? ghost.offer.flatMap { arrivals.smartName(for: $0) }
                        : nil,
                    usesScreenshotPlaceholder: smartNames.isEnabled
                ),
                // Match an adopted row's stable trailing slot. The ghost does not draw
                // the arrow yet, but reserving its room prevents title truncation and
                // keeps the card from changing width when clicked.
                showsAction: theme.showsDeleteButton,
                // A ghost has no drop record yet, so it can never carry a learned route.
                showsRouteAction: false
            )
        } : []
        let contentWidth = RowMetrics.contentHuggingCardWidth(
            rows: itemRows + ghostRows,
            theme: theme,
            maximumWidth: maximumListWidth
        )
        guard usesStabilizedNameWidth else { return contentWidth }
        return max(
            contentWidth,
            RowMetrics.stabilizedSmartNameCardWidth(
                maximumWidth: maximumListWidth
            )
        )
    }

    /// Width of the empty drop tile at 100% size. Style-independent — the tile's artwork
    /// (a fixed-size symbol) is identical in both styles, so the card must not change
    /// size when the style switches — but it does follow the user's size slider, like
    /// everything else.
    private static let emptyCardWidth: CGFloat = 80

    /// Width of the compact (icon-sized) card, for the empty drop target and icons-only mode.
    private var compactCardWidth: CGFloat {
        let theme = themeStore.theme
        return theme.contentPadding * 2 + 20 + theme.iconSize + 14
    }

    /// The floating-card frame on a given screen + edge: inset from that edge so the
    /// edge tab's catch zone (wider than the margin) still overlaps the panel — no
    /// dead zone on the hand-off. Height tracks the content, capped to the screen.
    private static func panelFrame(for screen: NSScreen, edge: ShelfEdge, contentHeight: CGFloat, width: CGFloat, centerY: CGFloat?) -> NSRect {
        let visibleFrame = screen.visibleFrame

        if edge == .notch {
            // A card hanging from the notch: centered on it, dropping down from just
            // below the menu bar.
            let width = min(width, visibleFrame.width - 16)
            let height = min(contentHeight, visibleFrame.height - 40)
            let interval = EdgeStripWindow.notchXInterval(for: screen)
            let centerX = (interval.min + interval.max) / 2
            let x = min(max(centerX - width / 2, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
            let y = visibleFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        }

        let margin: CGFloat = 12
        let width = min(width, visibleFrame.width - margin)
        // Grow freely to fit the contents; only the physical screen height bounds it.
        let height = min(contentHeight, visibleFrame.height - 24)
        // Anchor on the cursor's Y when we have one (so the card opens beside the drag),
        // clamped to stay fully on-screen; otherwise fall back to vertical center.
        let y: CGFloat
        if let centerY {
            let lowerBound = visibleFrame.minY + 12
            let upperBound = visibleFrame.maxY - height - 12
            y = min(max(centerY - height / 2, lowerBound), max(lowerBound, upperBound))
        } else {
            y = visibleFrame.minY + (visibleFrame.height - height) / 2
        }
        let x = edge == .left ? visibleFrame.minX + margin : visibleFrame.maxX - width - margin

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func installEdgeStripIfNeeded() {
        guard edgeStrips.isEmpty else {
            return
        }

        guard !NSScreen.screens.isEmpty else {
            NSLog("Perch edge tab not installed: no screen available")
            return
        }

        var strips: [EdgeStripWindow] = []
        if edgeSettings.isEnabled(.right) {
            for screen in Self.screensWithOuterEdge(.right) {
                strips.append(makeStrip(on: screen, edge: .right))
            }
        }
        if edgeSettings.isEnabled(.left) {
            for screen in Self.screensWithOuterEdge(.left) {
                strips.append(makeStrip(on: screen, edge: .left))
            }
        }
        if edgeSettings.isEnabled(.notch) {
            for screen in NSScreen.screens where EdgeStripWindow.hasNotch(screen) {
                strips.append(makeStrip(on: screen, edge: .notch))
            }
        }
        edgeStrips = strips
        NSLog("Perch installed \(strips.count) edge tab(s) across \(NSScreen.screens.count) screen(s)")
    }

    /// Tear down and recreate the edge tabs for the current screen layout. If the shelf
    /// is open on a display that's gone, retract it so it can't be stranded off-screen.
    private func rebuildEdgeStrips() {
        for strip in edgeStrips {
            strip.orderOut(nil)
        }
        edgeStrips.removeAll()
        installEdgeStripIfNeeded()

        // Retract if the shelf is open on a screen that's gone or an edge now disabled.
        let screenGone = shownScreen.map { !NSScreen.screens.contains($0) } ?? false
        if panel.isVisible, revealMode == .edge, screenGone || !edgeSettings.isEnabled(shownEdge) {
            if screenGone {
                preferredScreen = nil
                shownScreen = nil
            }
            hideShelf(animated: false)
        }
        relocateStrandedFreeShelf()
        NSLog("Perch rebuilt edge tabs (\(NSScreen.screens.count) screen(s), edges \(edgeSettings.enabledEdges.map(\.rawValue).sorted()))")
    }

    /// A free-floating shelf pinned on a display that's gone (or rearranged away) would
    /// otherwise stay "visible" at coordinates outside every live screen — unreachable
    /// forever, because a visible panel blocks every reveal path, the edge tabs are inert
    /// in free mode, and a free shelf never auto-retracts. Re-pin it onto a live screen,
    /// centered (the dead display's coordinates mean nothing on this one).
    private func relocateStrandedFreeShelf() {
        guard revealMode == .free, panel.isVisible else { return }
        if let pinned = summonScreen, !NSScreen.screens.contains(pinned) {
            summonScreen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
                ?? NSScreen.main ?? NSScreen.screens.first
        }
        guard !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) else { return }
        NSLog("Perch relocating stranded free shelf from \(NSStringFromRect(panel.frame))")
        summonScreen = NSScreen.main ?? NSScreen.screens.first
        freeTopLeft = nil
        windowController.resize(to: freePanelFrame(), animated: false)
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    /// Reopening the app (Finder/Dock double-click) is the one affordance left when the
    /// shelf is unreachable — rescue anything stranded and bring the shelf into view.
    func handleReopen() {
        if revealMode == .free {
            relocateStrandedFreeShelf()
            windowController.ensurePresented()
            return
        }
        // Reopen is also the recovery affordance for a panel whose AppKit visibility,
        // render state, and interaction state diverged during menu tracking. Clear all
        // transient holds and perform a real reveal even if `isVisible` claims the
        // panel is already open; the reveal invalidates any stale hide completion and
        // restores the canonical edge frame/alpha/front ordering.
        cancelOpen()
        cancelRetract()
        stopRetractWatcher()
        pointerInRegion = false
        revealedForDrag = false
        dragOutDockedFrame = nil
        hostView.resetInteraction()
        preferredScreen = Self.liveScreen(shownScreen ?? preferredScreen)
        preferredEdge = shownEdge
        revealAtPreferredEdge()
        startRetractWatcher()
    }

    /// Menu tracking may consume the mouse exit/up that normally clears hover and drag
    /// holds. Rebuild the keep-open decision from the actual cursor when it ends.
    private func contextMenuDidClose() {
        guard revealMode == .edge, panel.isVisible else { return }
        let overShelf = pointerOverShelfOrTab(NSEvent.mouseLocation)
        pointerInRegion = overShelf
        if !dragActive {
            revealedForDrag = false
            dragOutDockedFrame = nil
        }
        startRetractWatcher()
        guard !overShelf, store.items.isEmpty else { return }
        scheduleRetract(immediate: true)
    }

    /// `screen` if it's still attached, else the main/first live screen. Stale NSScreen
    /// references (kept across a display disconnect) answer frame queries in a dead
    /// coordinate space, which is how a card ends up outside every live screen.
    private static func liveScreen(_ screen: NSScreen?) -> NSScreen? {
        if let screen, NSScreen.screens.contains(screen) { return screen }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func makeStrip(on screen: NSScreen, edge: ShelfEdge) -> EdgeStripWindow {
        let strip = EdgeStripWindow(screen: screen, edge: edge, themeStore: themeStore)
        strip.stripDelegate = self
        strip.orderFrontRegardless()
        NSLog("Perch edge tab (\(edge)) installed at frame \(NSStringFromRect(strip.frame))")
        return strip
    }

    /// Screens whose given edge is a true outer edge of the desktop — i.e. no other
    /// screen sits immediately beyond it (which would make the edge an internal seam
    /// and put a useless tab in the middle of the desktop).
    private static func screensWithOuterEdge(_ edge: ShelfEdge) -> [NSScreen] {
        let screens = NSScreen.screens
        return screens.filter { screen in
            let edgeX = edge == .left ? screen.frame.minX : screen.frame.maxX
            let hasNeighborBeyond = screens.contains { other in
                guard other != screen,
                      other.frame.minY < screen.frame.maxY,
                      other.frame.maxY > screen.frame.minY else {
                    return false
                }
                return edge == .left
                    ? abs(other.frame.maxX - edgeX) < 1
                    : abs(other.frame.minX - edgeX) < 1
            }
            return !hasNeighborBeyond
        }
    }

    /// The pointer (hover or drag) entered the tab or panel. Drags reveal at once;
    /// a plain hover waits briefly so brushing past the edge does not pop it open.
    private func enterRegion(immediate: Bool) {
        cancelRetract()

        if immediate {
            cancelOpen()
            pointerInRegion = true
            revealIfNeeded()
            return
        }

        cancelOpen()
        openTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.pointerInRegion = true
            self.revealIfNeeded()
            self.openTask = nil
        }
    }

    /// The pointer left the region. A plain hover exit retracts immediately. Drag exits
    /// are *ignored* here: the card emits spurious exit events while it animates and
    /// resizes in, which would yank an empty shelf out from under an in-flight drop —
    /// the retract watcher governs the drag case from the real cursor position instead.
    private func exitRegion(duringDrag: Bool) {
        cancelOpen()
        // A free-floating shelf is persistent — it ignores pointer-out and manages its
        // own dismissal (✕ or emptying out).
        if revealMode == .free { return }
        // A fast drag-to-pin can outrun the card between drag events; don't let the
        // momentary exit retract an empty card mid-gesture.
        if dragOutDockedFrame != nil { return }
        // Tracking areas can report an ordinary mouse exit while AppKit is actually
        // routing a system drag. The controller's global drag state is authoritative.
        if duringDrag || dragActive { return }
        pointerInRegion = false
        // A context menu open over the shelf keeps it alive even as the pointer wanders
        // into submenus outside the card.
        if hostView.isContextMenuOpen { return }
        guard store.items.isEmpty else { return }
        // Moving off the (centered) card toward the tab still reads as a card-exit, but
        // it's really a hand-off across the gap — only retract instantly when the pointer
        // has actually left the whole tab↔card corridor; otherwise let the watcher decide.
        if pointerOverShelfOrTab(NSEvent.mouseLocation) { return }
        scheduleRetract(immediate: true)
    }

    /// While the shelf is open, poll the real cursor position and retract once it's
    /// empty and the pointer has left both the card and the tab. Polling (rather than
    /// the panel's own enter/exit events) stays correct across the reveal animation,
    /// the resize-to-fit, and drops that swallow the mouse-up — all of which make the
    /// per-window drag events unreliable.
    private func startRetractWatcher() {
        retractWatcher?.cancel()
        retractWatcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self, !Task.isCancelled, self.panel.isVisible else { return }
                // Self-heal a stuck overflow-scroll offset while the shelf is open (a
                // drop mid-drag can defer the resize past the clamp in
                // contentHeightDidChange), and a sheared contentView (see
                // healContentViewShear) no matter what produced it.
                self.hostView.clampScrollToTopIfContentFits()
                self.windowController.healContentViewShear()
                let pointerIsOverShelf = self.pointerOverShelfOrTab(
                    NSEvent.mouseLocation
                )
                guard self.shouldAutomaticallyRetractEmptyShelf(
                    pointerInKeepAliveRegion: pointerIsOverShelf
                ) else {
                    continue
                }
                self.hostView.resetInteraction()
                self.windowController.hide(animated: true)
                return
            }
        }
    }

    private func stopRetractWatcher() {
        retractWatcher?.cancel()
        retractWatcher = nil
    }

    /// Whether the cursor is within the keep-open corridor: the card, any tab, or the
    /// span bridging the active tab to the (centered) card — so carrying a drag from the
    /// tab across the gap to the card never reads as "left the shelf" (screen coords).
    private func pointerOverShelfOrTab(_ point: NSPoint) -> Bool {
        if keepAliveRegion().contains(point) { return true }
        return edgeStrips.contains { $0.catchZoneContains(point) }
    }

    /// The card's frame unioned with the active edge's tab, so the rectangle spans the
    /// whole corridor between the tab and the centered card.
    private func keepAliveRegion() -> NSRect {
        var region = panel.frame.insetBy(dx: -14, dy: -14)
        if let tab = edgeStrips.first(where: { $0.edge == shownEdge }) {
            region = region.union(tab.frame)
        }
        return region
    }

    /// Open and stay open while the shelf holds items; retract once empty (unless the
    /// pointer is hovering it).
    private func shelfContentDidChange(isEmpty: Bool) {
        if isEmpty {
            // A free shelf lives until it empties (the last item left) — then it's done,
            // unless "Keep Open When Empty" pins it in place as the empty drop tile.
            if revealMode == .free {
                if keepsEmptyFreeShelf {
                    // The last measurement still reflects the departed rows; drop it so
                    // the card animates down to the empty tile's estimated size.
                    measuredContentHeight = nil
                    resizeToFitVisible()
                } else {
                    dismissFreeShelf()
                }
            } else if !pointerInRegion {
                scheduleRetract()
            }
        } else {
            cancelRetract()
            revealIfNeeded()
        }
    }

    private func revealIfNeeded() {
        cancelRetract()
        startRetractWatcher()
        guard !panel.isVisible else {
            // Treat edge activation as a repair signal too. AppKit can report a panel
            // visible after menu/animation races even though its alpha, content layer,
            // or ordering no longer matches that state.
            windowController.ensurePresented()
            return
        }
        refreshArrivals(markRevealed: true)
        revealAtPreferredEdge()
    }

    /// Reveal (or reposition) the panel at the current preferred screen + edge.
    private func revealAtPreferredEdge() {
        // `preferredEdge` can be stale (including its launch default of `.right`) after
        // settings change. Resolve it through the installed strips—the authoritative
        // set of enabled, physically available docks—before any reveal. This keeps
        // automatic arrival/screenshot reveals off disabled edges too.
        guard let strip = resolvedPreferredStrip() else {
            NSLog("Perch reveal skipped: no enabled edge dock is available")
            return
        }
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        persistPreferredEdge()
        clearSystemDockAttachment()

        // Docking at an edge clears any leftover free-mode layout, including the lock.
        dismissingFreeShelfResetTask?.cancel()
        dismissingFreeShelfResetTask = nil
        dismissingFreeShelf = false
        revealMode = .edge
        freeShelfLocked = false
        hostView.setLockedInPlace(false)
        hostView.setFreeMode(false)
        let screen = Self.liveScreen(preferredScreen)
        shownScreen = screen
        shownEdge = preferredEdge
        let frame = screen.map { panelFrame(for: $0, edge: preferredEdge) } ?? Self.initialPanelFrame()
        windowController.reveal(
            animated: true,
            targetFrame: frame,
            edge: preferredEdge
        )
    }

    /// Preserve the current preference when it still names an installed dock. If its
    /// edge was disabled or its screen disappeared, fall back to the closest enabled
    /// strip instead of silently drawing the shelf on the stale edge.
    private func resolvedPreferredStrip() -> EdgeStripWindow? {
        if let preferredScreen,
           let exact = edgeStrips.first(where: {
               $0.edge == preferredEdge && $0.pinnedScreen == preferredScreen
           }) {
            return exact
        }

        let point = NSEvent.mouseLocation
        let sameEdge = edgeStrips.filter { $0.edge == preferredEdge }
        if let nearestOnPreferredEdge = sameEdge.min(by: {
            Self.distance(from: point, to: $0.frame) < Self.distance(from: point, to: $1.frame)
        }) {
            return nearestOnPreferredEdge
        }
        return nearestStrip(to: point)
    }

    private func persistPreferredEdge() {
        UserDefaults.standard.set(
            preferredEdge.rawValue,
            forKey: Self.preferredEdgeKey
        )
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func cancelRetract() {
        retractTask?.cancel()
        retractTask = nil
    }

    /// Retract the shelf back to the tab. A hover exit passes `immediate` for a
    /// zero-delay dismissal; a drag exit keeps a brief grace so the tab↔panel
    /// hand-off (which fires a spurious exit then re-enter) isn't cut off. Either way
    /// a re-enter or new content cancels it.
    private func scheduleRetract(immediate: Bool = false) {
        cancelRetract()
        retractTask = Task { @MainActor [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            // Re-check every visibility hold, including a system drag that may have
            // begun after this task was scheduled.
            guard self.shouldAutomaticallyRetractEmptyShelf(
                pointerInKeepAliveRegion: self.pointerInRegion
            ) else {
                self.retractTask = nil
                return
            }
            self.hostView.resetInteraction()
            self.windowController.hide(animated: true)
            self.retractTask = nil
        }
    }

    private func shouldAutomaticallyRetractEmptyShelf(
        pointerInKeepAliveRegion: Bool
    ) -> Bool {
        ShelfRetractionPolicy.shouldRetractEmptyShelf(
            dragActive: dragActive,
            shelfDragActive: dragOutDockedFrame != nil,
            isFreeFloating: revealMode == .free,
            isEmpty: store.items.isEmpty,
            pointerInKeepAliveRegion: pointerInKeepAliveRegion,
            contextMenuOpen: hostView.isContextMenuOpen
        )
    }

    private func hideShelf(animated: Bool) {
        cancelRetract()
        stopRetractWatcher()
        hostView.resetInteraction()
        windowController.hide(animated: animated)
    }

    /// Wait for every asynchronous part of a stored item before recording it. This
    /// prevents the log from observing promise placeholders, half-copied files, or a
    /// fallback copy that is about to fail and remove its shelf row.
    private func finalizeDrop(
        _ result: PasteboardSnapshotResult,
        initialCount: Int,
        recordingContext: DropRecordingContext
    ) {
        let hasPromises = !result.pendingPromises.isEmpty
        let hasCopies = !result.pendingCopies.isEmpty
        let payloadKind: DropPayloadKind

        if hasPromises && (hasCopies || !result.item.backingFileURLs().isEmpty) {
            payloadKind = .mixed
        } else if hasPromises {
            payloadKind = .filePromise
        } else if result.item.backingFileURLs().isEmpty {
            payloadKind = .clipping
        } else {
            payloadKind = .file
        }

        let finishAfterCopies: @MainActor (Bool) -> Void = { [weak self] copiesSucceeded in
            guard let self, copiesSucceeded else { return }

            if hasPromises {
                self.materializePendingPromises(
                    for: result.item,
                    receivers: result.pendingPromises,
                    initialCount: initialCount,
                    recordingContext: recordingContext,
                    payloadKind: payloadKind
                )
            } else {
                self.recordSmartDrop(
                    result.item,
                    context: recordingContext,
                    payloadKind: payloadKind
                )
            }
        }

        if hasCopies {
            performDeferredCopies(
                result.pendingCopies,
                for: result.item,
                completion: finishAfterCopies
            )
        } else {
            finishAfterCopies(true)
        }
    }

    private func performDeferredCopies(
        _ copies: [(source: URL, destination: URL)],
        for item: StoredItem,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            var failed = false
            for copy in copies {
                do {
                    try FileManager.default.copyItem(at: copy.source, to: copy.destination)
                } catch {
                    NSLog("Perch deferred copy failed for \(copy.source.path): \(error)")
                    failed = true
                }
            }
            let copiesSucceeded = !failed
            guard let self else { return }
            await MainActor.run {
                if !copiesSucceeded {
                    self.store.remove(item)
                }
                completion(copiesSucceeded)
            }
        }
    }

    private func materializePendingPromises(
        for item: StoredItem,
        receivers: [NSFilePromiseReceiver],
        initialCount: Int,
        recordingContext: DropRecordingContext,
        payloadKind: DropPayloadKind
    ) {
        let filesDir = item.directoryURL.appendingPathComponent("files", isDirectory: true)
        let reconciliation = PromiseMaterializationReconciler()

        promiseMaterializer.materialize(
            receivers,
            into: filesDir,
            lateDelivery: { [weak self] fileURL in
                Task { @MainActor [weak self] in
                    guard let self,
                          let reconciledURL = reconciliation.reconcileLate(fileURL)
                    else { return }
                    self.appendLateMaterializedFile(
                        reconciledURL,
                        toItemID: item.id,
                        droppedAt: recordingContext.occurredAt
                    )
                }
            }
        ) { [weak self] materializedURLs in
            Task { @MainActor [weak self] in
                let reconciledURLs = reconciliation.reconcileInitial(materializedURLs)
                guard let self else { return }

                let beforeInsertMainThread = pthread_main_np() == 1
                do {
                    let finalItem = try self.itemByAppendingMaterializedFiles(
                        reconciledURLs,
                        to: item
                    )
                    self.beginDropLayoutMutation()
                    defer { self.endDropLayoutMutation() }
                    self.arrivals.excludeRecentlyMatchingCopies(
                        of: reconciledURLs,
                        droppedAt: recordingContext.occurredAt
                    )
                    self.registerScreenshotPresentationIfNeeded(for: finalItem)
                    self.store.insert(finalItem, at: nil)

                    let repTypes = finalItem.metadata.representations.map(\.typeIdentifier).joined(separator: ",")
                    let backingFiles = finalItem.backingFileURLs().map(\.lastPathComponent).joined(separator: ",")
                    NSLog(
                        "Perch promise materialization stored item \(finalItem.id.uuidString); count \(initialCount)->\(self.store.items.count); reps [\(repTypes)]; files [\(backingFiles)]; mainThread \(beforeInsertMainThread)"
                    )
                    self.recordSmartDrop(
                        finalItem,
                        context: recordingContext,
                        payloadKind: payloadKind
                    )
                } catch {
                    NSLog("Perch promise materialization failed for item \(item.id.uuidString): \(error)")
                    try? FileManager.default.removeItem(at: item.directoryURL)
                }
            }
        }
    }

    /// Append a promise that arrived after the timeout-created row was inserted. If
    /// the user has already removed or vended the row, delete only the untracked late
    /// file so it cannot become an orphan in the retained item directory.
    private func appendLateMaterializedFile(
        _ fileURL: URL,
        toItemID itemID: UUID,
        droppedAt: Date
    ) {
        guard let currentItem = store.items.first(where: { $0.id == itemID }) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard !currentItem.metadata.backingFileNames.contains(fileURL.lastPathComponent)
        else { return }

        do {
            let updatedItem = try itemByAppendingMaterializedFiles(
                [fileURL],
                to: currentItem
            )
            guard store.replace(updatedItem) else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            arrivals.excludeRecentlyMatchingCopies(
                of: [fileURL],
                droppedAt: droppedAt
            )
            registerScreenshotPresentationIfNeeded(for: updatedItem)
            NSLog(
                "Perch appended late promise delivery \(fileURL.lastPathComponent) to item \(itemID.uuidString)"
            )
        } catch {
            NSLog(
                "Perch could not append late promise delivery \(fileURL.path): \(error)"
            )
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func itemByAppendingMaterializedFiles(
        _ materializedURLs: [URL],
        to item: StoredItem
    ) throws -> StoredItem {
        var metadata = item.metadata
        var knownFileNames = Set(metadata.backingFileNames)
        let newFileNames = materializedURLs.compactMap { url -> String? in
            let fileName = url.lastPathComponent
            guard !fileName.isEmpty, knownFileNames.insert(fileName).inserted else {
                return nil
            }
            return fileName
        }

        metadata.backingFileNames.append(contentsOf: newFileNames)
        if metadata.backingFileNames.count == newFileNames.count,
           let firstFileName = newFileNames.first {
            metadata.title = firstFileName
        }

        let metaURL = item.directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return StoredItem(metadata: metadata, directoryURL: item.directoryURL)
    }

    private func recordSmartDrop(
        _ item: StoredItem,
        context: DropRecordingContext,
        payloadKind: DropPayloadKind,
        screenshotCaptureContexts: [ScreenshotCaptureContext?]? = nil,
        prefetchedOCRResults: [ScreenshotOCRResult?]? = nil
    ) {
        smart?.recordDrop(
            item,
            context: context,
            payloadKind: payloadKind,
            screenshotCaptureContexts: screenshotCaptureContexts,
            prefetchedOCRResults: prefetchedOCRResults
        )
    }

    @discardableResult
    private func registerScreenshotPresentationIfNeeded(
        for item: StoredItem
    ) -> Bool {
        smart?.registerScreenshotPresentationIfNeeded(for: item) ?? false
    }
}
