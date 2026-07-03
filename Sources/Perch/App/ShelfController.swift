import AppKit
import Combine
import Darwin

/// `@MainActor` coordinator that wires the store, windows, and the three pipelines.
@MainActor
final class ShelfController: ShelfDropHandling, EdgeStripDelegate {
    private let panel: ShelfPanel
    private let windowController: ShelfWindowController
    private let holding: HoldingDirectory
    private let store: ItemStore
    private let ledger: ProvenanceLedger
    private let historyWindow: HistoryWindowController
    private let snapshotter: PasteboardSnapshotter
    private let promiseMaterializer: FilePromiseMaterializer
    private let dropView: ShelfDropView
    private let hostView: ShelfHostView
    private let themeStore = ThemeStore()
    private let edgeSettings = EdgeSettings()
    private var edgeStrips: [EdgeStripWindow] = []
    private let mouseMonitor = MouseMonitor()
    private var openTask: Task<Void, Never>?
    private var retractTask: Task<Void, Never>?
    private var pointerInRegion = false
    /// True while a system drag is in flight; grows the empty drop target.
    private var dragActive = false
    /// True when the current drag (in "reveal while dragging" mode) is what opened the
    /// shelf, so it follows the nearest edge during the drag and retracts on drag-end if
    /// nothing was dropped onto it.
    private var revealedForDrag = false

    /// Whether the shelf should pop out at the nearest enabled edge the instant a drag
    /// starts (vs. waiting for the pointer to reach the edge tab). User-toggled.
    private var revealOnDragStart: Bool {
        UserDefaults.standard.bool(forKey: ShelfHostView.revealOnDragStartKey)
    }
    /// Whether the shake-to-summon gesture is active. User-toggled; defaults on (an unset
    /// value reads as true), matching the original always-on behavior.
    private var shakeToSummonEnabled: Bool {
        UserDefaults.standard.object(forKey: ShelfHostView.shakeToSummonKey) as? Bool ?? true
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
    /// True while a row-removal animation is in flight. The rows animate their shrink,
    /// so the measured height streams a new value every frame; acting on each one would
    /// snap-resize (and re-center) the window per frame — the visible "clunk". Instead
    /// the window animates once to the exact final frame and measured heights are
    /// ignored until the dust settles.
    private var removalResizeInFlight = false
    private var removalResizeTask: Task<Void, Never>?
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
    private var labelsCancellable: AnyCancellable?
    private var grabHandleCancellable: AnyCancellable?

    /// Where the shelf is currently anchored: docked to a screen edge, or free-floating
    /// at the cursor (shake-to-summon). The two coexist on the same panel.
    private enum RevealMode { case edge, free }
    private var revealMode: RevealMode = .edge
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
    /// Observes user-initiated window moves so a dragged free shelf keeps its new origin.
    private var windowMoveObserver: NSObjectProtocol?

    init() throws {
        holding = try HoldingDirectory.standard()
        store = ItemStore(holding: holding)
        ledger = ProvenanceLedger(holding: holding)
        historyWindow = HistoryWindowController(ledger: ledger)
        snapshotter = PasteboardSnapshotter(holding: holding)
        promiseMaterializer = FilePromiseMaterializer()
        panel = ShelfPanel(contentRect: Self.initialPanelFrame())
        windowController = ShelfWindowController(panel: panel)
        dropView = ShelfDropView(frame: panel.contentView?.bounds ?? .zero)
        hostView = ShelfHostView(store: store, themeStore: themeStore, edgeSettings: edgeSettings, ledger: ledger)
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

        // "Close Shelf" in the context menu dismisses the free shelf without removing
        // any stored items.
        hostView.onCloseFreeShelf = { [weak self] in self?.dismissFreeShelf() }

        // An empty tile can also be dismissed by clicking its body.
        hostView.onDismissEmptyFree = { [weak self] in self?.dismissFreeShelf() }

        // Deleting the last item hides the card before the store empties, so the
        // empty-state swap happens off-screen instead of flashing mid-dismissal.
        hostView.onWillRemoveLastItem = { [weak self] in
            guard let self else { return }
            if self.revealMode == .free {
                self.dismissFreeShelf()
            } else {
                self.hideShelf(animated: true)
            }
        }

        // Dragging the card's grab handle or its background (not a row) moves the whole
        // card. From an edge it tears the docked shelf off: past a small distance it
        // pins where it's dropped as a free-floating shelf, otherwise it snaps back. A
        // free shelf just moves (its new origin is kept by the didMove observer). The
        // "Show Drag Handle" toggle is the single switch for the docked drag-out; a free
        // shelf stays movable regardless so it can never get stuck.
        hostView.canBeginShelfDrag = { [weak self] in
            guard let self, self.panel.isVisible else { return false }
            return self.revealMode == .free || self.themeStore.showsGrabHandle
        }
        hostView.onShelfDragBegan = { [weak self] in
            guard let self else { return }
            if self.revealMode == .edge {
                self.dragOutDockedFrame = self.panel.frame
            }
            self.cancelOpen()
            self.cancelRetract()
        }
        hostView.onShelfDragEnded = { [weak self] in
            self?.shelfDragDidEnd()
        }

        // Grow/shrink the window to the SwiftUI content's actual measured height.
        hostView.onContentHeight = { [weak self] height in
            self?.contentHeightDidChange(height)
        }

        hostView.onShowHistory = { [weak self] in
            self?.historyWindow.show()
        }

        // Reinstall the edge tabs whenever the user enables/disables an edge dock.
        edgeSettings.onChange = { [weak self] in
            self?.rebuildEdgeStrips()
        }
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        do {
            try store.load()
            ledger.load()
            NSLog("Perch loaded \(store.items.count) stored item(s)")
        } catch {
            NSLog("Perch failed to load stored items: \(error)")
        }

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

        // During a drag, show only the tab nearest the cursor; hide all when it ends.
        // The drag also grows the empty drop target into a bigger, easier box.
        mouseMonitor.onDragSessionChange = { [weak self] active in
            guard let self else { return }
            self.setDragActive(active)
            if active {
                self.showNearestTab(to: NSEvent.mouseLocation)
                if self.revealOnDragStart {
                    self.revealForDrag(to: NSEvent.mouseLocation)
                }
            } else {
                self.setTabsShown(false)
                self.dragDidEnd()
            }
        }
        mouseMonitor.onDragMoved = { [weak self] point in
            guard let self else { return }
            self.showNearestTab(to: point)
            if self.revealedForDrag {
                self.followNearestEdge(to: point)
            }
        }
        // Shake the cursor to summon the shelf right where the pointer is (when enabled).
        mouseMonitor.onSummonAtCursor = { [weak self] point in
            guard let self, self.shakeToSummonEnabled else { return }
            self.summonAtCursor(point)
        }
        mouseMonitor.start()

        // Keep a dragged free shelf's chosen position: when the user moves the panel via
        // the grab handle, remember its new top-left so content resizes grow from there.
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.captureFreeOrigin() }
        }

        // Resize the card to hug its contents on every change, and stay open while it
        // holds items / retract when empty. Subscribing fires immediately with the
        // loaded items.
        itemsCancellable = store.$items
            .sink { [weak self] items in
                self?.shelfItemsDidChange(items)
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

        // Showing/hiding the grab handle changes the card's height by the handle strip —
        // same willSet/next-pass dance as the labels toggle. The stale measured height
        // (still including/excluding the old strip) is dropped so the estimate drives
        // one animated re-fit instead of waiting for the snap.
        grabHandleCancellable = themeStore.$showsGrabHandle
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.measuredContentHeight = nil
                self?.resizeToFitVisible()
            }

        // TEMPORARY DEBUG HARNESS (remove): simulate Finder-style drops so the
        // post-drop layout bug can be reproduced and observed without a live drag.
        // PERCH_TEST_DROP is a colon-separated list of file paths; each becomes one
        // simulated drop 2s apart, with geometry logged around it.
        if let spec = ProcessInfo.processInfo.environment["PERCH_TEST_DROP"] {
            runTestDrops(paths: spec.split(separator: ":").map(String.init))
        }
        if ProcessInfo.processInfo.environment["PERCH_TEST_GEOM"] != nil {
            Task { @MainActor [weak self] in
                while true {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self else { return }
                    guard self.panel.isVisible else { continue }
                    NSLog("PerchGEOM panel=\(NSStringFromRect(self.panel.frame)) content=\(NSStringFromRect(self.panel.contentView?.frame ?? .zero)) \(self.hostView.debugGeometry()) measured=\(self.measuredContentHeight ?? -1) count=\(self.store.items.count)")
                }
            }
        }
    }

    // TEMPORARY DEBUG HARNESS (remove with the env hook above).
    private func runTestDrops(paths: [String]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(2))
            // Mirror the real flow: a drag session starts, the shelf reveals empty,
            // then the drop lands while the card is visible with drag state active.
            self.setDragActive(true)
            self.revealAtPreferredEdge()
            try? await Task.sleep(for: .seconds(1))
            for path in paths {
                let pasteboard = NSPasteboard(name: NSPasteboard.Name("perch-test-\(UUID().uuidString)"))
                pasteboard.clearContents()
                pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
                let ok = self.handleDrop(pasteboard)
                NSLog("PerchTEST drop ok=\(ok) path=\(path) frame=\(NSStringFromRect(self.panel.frame)) measured=\(self.measuredContentHeight ?? -1)")
                try? await Task.sleep(for: .seconds(2))
                NSLog("PerchTEST settle frame=\(NSStringFromRect(self.panel.frame)) measured=\(self.measuredContentHeight ?? -1) count=\(self.store.items.count) scrollY=\(self.hostView.debugScrollOffsetY())")
            }
            self.setDragActive(false)
            // Simulate what a drag autoscroll / elastic scroll leaves behind: a stuck
            // offset on the (normally invisible) overflow ScrollView.
            if let forced = ProcessInfo.processInfo.environment["PERCH_TEST_SCROLL"].flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(1))
                self.hostView.debugForceScroll(CGFloat(forced))
                NSLog("PerchTEST forced scrollY=\(self.hostView.debugScrollOffsetY())")
            }
            for _ in 0..<6 {
                try? await Task.sleep(for: .seconds(1))
                NSLog("PerchTEST idle frame=\(NSStringFromRect(self.panel.frame)) measured=\(self.measuredContentHeight ?? -1) count=\(self.store.items.count) scrollY=\(self.hostView.debugScrollOffsetY())")
            }
        }
    }

    /// React to the item list changing: shrink smoothly on removals, and run the
    /// open/retract logic when the empty↔non-empty state actually flips. (Growth on
    /// insertions is driven separately by the SwiftUI content's measured height — see
    /// `contentHeightDidChange`.)
    private func shelfItemsDidChange(_ items: [StoredItem]) {
        let previousCount = lastItemCount
        lastItemCount = items.count
        let isEmpty = items.isEmpty
        if items.count < previousCount, !isEmpty {
            animateRemovalResize()
        } else if items.count > previousCount {
            // New content arriving cancels any in-flight removal shrink so the card can
            // grow for it right away.
            endRemovalResize()
        }
        guard isEmpty != wasEmpty else { return }
        wasEmpty = isEmpty
        shelfContentDidChange(isEmpty: isEmpty)
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
            self?.resizeToFitVisible(animated: false)
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
        } else if let screen = shownScreen ?? NSScreen.main ?? NSScreen.screens.first {
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

    /// The rows have settled — resume measured-height-driven sizing and true-up once
    /// (a no-op when the animation landed where expected).
    private func endRemovalResize() {
        removalResizeTask?.cancel()
        removalResizeTask = nil
        guard removalResizeInFlight else { return }
        removalResizeInFlight = false
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
        guard panel.isVisible else { return }
        // Mid drag-to-pin the card is following the cursor — don't refit it to an edge
        // frame out from under the gesture.
        if dragOutDockedFrame != nil { return }
        if revealMode == .free {
            windowController.resize(to: freePanelFrame(), animated: animated)
            return
        }
        guard let screen = shownScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        windowController.resize(to: panelFrame(for: screen, edge: shownEdge), animated: animated)
    }

    private func setTabsShown(_ shown: Bool) {
        for strip in edgeStrips {
            strip.showsTab = shown
        }
    }

    private func setDragActive(_ active: Bool) {
        dragActive = active
        if store.items.isEmpty {
            measuredContentHeight = nil
        }
        hostView.setDropTarget(active)
        // The drag ended somewhere off the shelf; make sure the outline is cleared even
        // if no draggingExited arrived.
        if !active {
            hostView.setDragOverShelf(false)
        }
        resizeToFitVisible()
    }

    /// Show only the tab whose catch zone is nearest the cursor.
    private func showNearestTab(to point: NSPoint) {
        guard let nearest = nearestStrip(to: point) else { return }
        for strip in edgeStrips {
            strip.showsTab = (strip === nearest)
        }
    }

    /// The enabled edge tab whose catch zone is nearest the cursor.
    private func nearestStrip(to point: NSPoint) -> EdgeStripWindow? {
        edgeStrips.min(by: {
            Self.distance(from: point, to: $0.frame) < Self.distance(from: point, to: $1.frame)
        })
    }

    /// "Reveal while dragging": open the shelf at the nearest enabled edge as the drag
    /// begins. Only flagged as drag-revealed if it wasn't already open, so a persistent
    /// (full) shelf is left where it is.
    private func revealForDrag(to point: NSPoint) {
        guard let strip = nearestStrip(to: point) else { return }
        if !panel.isVisible { revealedForDrag = true }
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        revealIfNeeded()
    }

    /// While a drag-revealed shelf is open, move it to whichever enabled edge the cursor
    /// is now nearest, so it tracks the pointer across edges/screens.
    private func followNearestEdge(to point: NSPoint) {
        guard let strip = nearestStrip(to: point),
              strip.edge != preferredEdge || strip.pinnedScreen != preferredScreen else { return }
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        revealAtPreferredEdge()
    }

    /// End of a drag: if it was the drag that opened the shelf and nothing landed on it
    /// (the cursor isn't over the shelf corridor), retract it back to the tab.
    private func dragDidEnd() {
        guard revealedForDrag else { return }
        revealedForDrag = false
        if pointerOverShelfOrTab(NSEvent.mouseLocation) { return }
        hostView.resetInteraction()
        windowController.hide(animated: true)
    }

    // MARK: Cursor summon (free-floating shelf)

    /// Shake-to-summon: bring the shelf to the cursor as a free-floating, movable card.
    /// Works whether the shelf is currently hidden or already docked at an edge.
    private func summonAtCursor(_ point: NSPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main ?? NSScreen.screens.first
        summonScreen = screen
        revealMode = .free
        freeSourceEdge = .right
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
        let screen = summonScreen ?? NSScreen.main ?? NSScreen.screens.first
        let visible = (screen ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let width = min(cardWidth(for: freeSourceEdge), visible.width - 16)
        let height = min(fittedContentHeight(), visible.height - 24)

        let anchor = freeTopLeft ?? NSPoint(x: visible.midX - width / 2, y: visible.midY + height / 2)
        let x = min(max(anchor.x, visible.minX + 8), visible.maxX - width - 8)
        // freeTopLeft is the top edge; convert to a bottom-left origin and clamp.
        let y = min(max(anchor.y - height, visible.minY + 8), visible.maxY - height - 8)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Remember the user's chosen position after they drag the free shelf by its handle.
    private func captureFreeOrigin() {
        guard revealMode == .free, panel.isVisible else { return }
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    // MARK: Drag-to-pin (tear the docked card off its edge)

    /// How far the card must travel from its docked frame to detach; released closer
    /// than this it snaps back to the edge and stays docked.
    private static let pinDetachDistance: CGFloat = 40

    /// Mouse-up on a drag-to-pin gesture: far enough from the docked frame, the card
    /// pins where it was dropped as a free-floating shelf (the same persistence as
    /// shake-to-summon); otherwise it snaps back to its edge.
    private func shelfDragDidEnd() {
        guard let docked = dragOutDockedFrame else { return }
        dragOutDockedFrame = nil
        let moved = hypot(panel.frame.minX - docked.minX, panel.frame.minY - docked.minY)
        if moved >= Self.pinDetachDistance {
            pinShelfAtCurrentPosition()
        } else {
            windowController.resize(to: docked)
        }
    }

    /// Convert the dragged-out card into a free-floating shelf pinned at its current
    /// position — the drag-out twin of `summonAtCursor`.
    private func pinShelfAtCurrentPosition() {
        summonScreen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main ?? NSScreen.screens.first
        revealMode = .free
        freeSourceEdge = shownEdge
        hostView.setFreeMode(true)
        cancelOpen()
        cancelRetract()
        stopRetractWatcher()
        pointerInRegion = false
        // Keep the card's top-left where the user dropped it; the free frame grows
        // downward from there and clamps on-screen.
        freeTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        windowController.usesFreeAnimation = true
        windowController.resize(to: freePanelFrame())
    }

    /// Tear down the free-floating shelf (✕ pressed, or it emptied out) and return to
    /// edge-docked behavior. Items, if any, stay in the store.
    private func dismissFreeShelf() {
        revealMode = .edge
        freeTopLeft = nil
        summonScreen = nil
        pointerInRegion = false
        stopRetractWatcher()
        cancelRetract()
        hostView.resetInteraction()
        windowController.hide(animated: true)
        // The host's free-mode behaviors are reset when the shelf next docks at an edge.
        windowController.usesFreeAnimation = false
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: ShelfDropHandling

    func handleDrop(_ pasteboard: NSPasteboard) -> Bool {
        let beforeCount = store.items.count

        do {
            let result = try snapshotter.snapshot(pasteboard, into: store)
            let afterCount = store.items.count
            let repTypes = result.item.metadata.representations.map(\.typeIdentifier).joined(separator: ",")
            let backingFiles = result.item.backingFileURLs().map(\.lastPathComponent).joined(separator: ",")

            NSLog(
                "Perch drop stored item \(result.item.id.uuidString); count \(beforeCount)->\(afterCount); reps [\(repTypes)]; files [\(backingFiles)]; pendingPromises \(result.pendingPromises.count)"
            )

            if !result.pendingPromises.isEmpty {
                materializePendingPromises(for: result.item, receivers: result.pendingPromises, initialCount: beforeCount)
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
        // Open the shelf on whichever screen + edge's tab was used.
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        // A drag reaching a tab while the shelf is open at a different edge means the
        // user is aiming for *this* perch — bring the shelf over to it.
        if viaDrag, panel.isVisible, revealMode == .edge,
           strip.edge != shownEdge || strip.pinnedScreen != shownScreen {
            revealAtPreferredEdge()
        }
        // Drags open immediately; a plain hover waits briefly so brushing past the
        // edge does not pop the shelf open.
        enterRegion(immediate: viaDrag)
    }

    func edgeStripPointerDidExit(_ strip: EdgeStripWindow, duringDrag: Bool) {
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

    /// The card height that hugs `itemCount` rows (or the empty-state height when zero;
    /// larger while dragging so the drop target is an easier box to hit). A populated
    /// card also carries the grab-handle strip above its rows, unless hidden.
    private func contentHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return dragActive ? Self.dropTargetHeight : Self.emptyStateHeight }
        let theme = themeStore.theme
        let grabber = themeStore.showsGrabHandle ? RowMetrics.grabberZoneHeight : 0
        let rows = CGFloat(itemCount) * theme.rowHeight
            + CGFloat(itemCount - 1) * theme.rowSpacing
        return theme.contentPadding * 2 + grabber + rows
    }

    /// The content-hugging card frame on a screen + edge. Prefers the actual measured
    /// SwiftUI height; falls back to a per-item estimate before the first measurement.
    private func panelFrame(for screen: NSScreen, edge: ShelfEdge) -> NSRect {
        Self.panelFrame(
            for: screen,
            edge: edge,
            contentHeight: fittedContentHeight(),
            width: cardWidth(for: edge),
            centerY: nil
        )
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

    /// The card's width on a given edge. Empty (and icons-only) it stays a compact strip
    /// just wide enough for an icon; once it holds items *and* names are shown it grows to
    /// a comfortable list width.
    private func cardWidth(for edge: ShelfEdge) -> CGFloat {
        if store.items.isEmpty {
            return compactCardWidth
        }
        guard themeStore.showsLabels else { return compactCardWidth }
        return edge == .notch ? 360 : 300
    }

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
        NSLog("Perch rebuilt edge tabs (\(NSScreen.screens.count) screen(s), edges \(edgeSettings.enabledEdges.map(\.rawValue).sorted()))")
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
        if duringDrag { return }
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
                // Don't pull the shelf out from under an open context menu — submenus
                // extend past the card, so the pointer reads as "left the shelf".
                if self.hostView.isContextMenuOpen { continue }
                // A free-floating shelf never auto-retracts on pointer-out.
                if self.revealMode == .free { continue }
                // The card follows the cursor during drag-to-pin; a momentary lag
                // behind a fast drag must not read as pointer-out.
                if self.dragOutDockedFrame != nil { continue }
                // While a drag is holding the shelf open ("reveal while dragging"), keep
                // it up regardless of pointer position; drag-end decides whether to close.
                if self.revealedForDrag { continue }
                // Persistent while full; only an empty shelf retracts on pointer-out.
                guard self.store.items.isEmpty else { continue }
                if self.pointerOverShelfOrTab(NSEvent.mouseLocation) { continue }
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
            // A free shelf lives until it empties (the last item left) — then it's done.
            if revealMode == .free {
                dismissFreeShelf()
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
        guard !panel.isVisible else { return }
        revealAtPreferredEdge()
    }

    /// Reveal (or reposition) the panel at the current preferred screen + edge.
    private func revealAtPreferredEdge() {
        // Docking at an edge clears any leftover free-mode layout.
        revealMode = .edge
        hostView.setFreeMode(false)
        let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        shownScreen = screen
        shownEdge = preferredEdge
        let frame = screen.map { panelFrame(for: $0, edge: preferredEdge) } ?? Self.initialPanelFrame()
        // Drag reveals slide in from the edge (the shelf chases the drag); hover reveals
        // just fade in place.
        windowController.reveal(animated: true, targetFrame: frame, edge: preferredEdge, slides: dragActive)
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
            // Re-check: content may have arrived, the pointer re-entered, or a context
            // menu opened.
            guard self.store.items.isEmpty, !self.pointerInRegion, !self.hostView.isContextMenuOpen else { return }
            self.hostView.resetInteraction()
            self.windowController.hide(animated: true)
            self.retractTask = nil
        }
    }

    private func hideShelf(animated: Bool) {
        cancelRetract()
        stopRetractWatcher()
        hostView.resetInteraction()
        windowController.hide(animated: animated)
    }

    private func materializePendingPromises(
        for item: StoredItem,
        receivers: [NSFilePromiseReceiver],
        initialCount: Int
    ) {
        let filesDir = item.directoryURL.appendingPathComponent("files", isDirectory: true)

        promiseMaterializer.materialize(receivers, into: filesDir) { [weak self] materializedURLs in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let beforeInsertMainThread = pthread_main_np() == 1
                do {
                    let finalItem = try self.itemByAppendingMaterializedFiles(
                        materializedURLs,
                        to: item
                    )
                    self.store.insert(finalItem, at: nil)

                    let repTypes = finalItem.metadata.representations.map(\.typeIdentifier).joined(separator: ",")
                    let backingFiles = finalItem.backingFileURLs().map(\.lastPathComponent).joined(separator: ",")
                    NSLog(
                        "Perch promise materialization stored item \(finalItem.id.uuidString); count \(initialCount)->\(self.store.items.count); reps [\(repTypes)]; files [\(backingFiles)]; mainThread \(beforeInsertMainThread)"
                    )
                } catch {
                    NSLog("Perch promise materialization failed for item \(item.id.uuidString): \(error)")
                    try? FileManager.default.removeItem(at: item.directoryURL)
                }
            }
        }
    }

    private func itemByAppendingMaterializedFiles(
        _ materializedURLs: [URL],
        to item: StoredItem
    ) throws -> StoredItem {
        var metadata = item.metadata
        let existingFileNames = Set(metadata.backingFileNames)
        let newFileNames = materializedURLs
            .map(\.lastPathComponent)
            .filter { !$0.isEmpty && !existingFileNames.contains($0) }

        metadata.backingFileNames.append(contentsOf: newFileNames)
        if metadata.backingFileNames.count == newFileNames.count,
           let firstFileName = newFileNames.first {
            metadata.title = firstFileName
        }

        let metaURL = item.directoryURL.appendingPathComponent("meta.json", isDirectory: false)
        try JSONEncoder().encode(metadata).write(to: metaURL, options: .atomic)

        return StoredItem(metadata: metadata, directoryURL: item.directoryURL)
    }
}
