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
    private let snapshotter: PasteboardSnapshotter
    private let promiseMaterializer: FilePromiseMaterializer
    private let dropView: ShelfDropView
    private let hostView: ShelfHostView
    private let themeStore = ThemeStore()
    private var edgeStrips: [EdgeStripWindow] = []
    private let mouseMonitor = MouseMonitor()
    private var openTask: Task<Void, Never>?
    private var retractTask: Task<Void, Never>?
    private var pointerInRegion = false
    /// Tracks the last empty/non-empty state so open/retract only runs on a real flip.
    private var wasEmpty: Bool?
    /// Latest measured SwiftUI content height, used to size the window to fit.
    private var measuredContentHeight: CGFloat?
    private var preferredScreen: NSScreen?
    private var preferredEdge: ShelfEdge = .right
    private var itemsCancellable: AnyCancellable?

    init() throws {
        holding = try HoldingDirectory.standard()
        store = ItemStore(holding: holding)
        snapshotter = PasteboardSnapshotter(holding: holding)
        promiseMaterializer = FilePromiseMaterializer()
        panel = ShelfPanel(contentRect: Self.initialPanelFrame())
        windowController = ShelfWindowController(panel: panel)
        dropView = ShelfDropView(frame: panel.contentView?.bounds ?? .zero)
        hostView = ShelfHostView(store: store, themeStore: themeStore)
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

        // Grow/shrink the window to the SwiftUI content's actual measured height.
        hostView.onContentHeight = { [weak self] height in
            self?.contentHeightDidChange(height)
        }
    }

    /// Build the windows, load the store, and start observing drags.
    func start() {
        do {
            try store.load()
            NSLog("Perch loaded \(store.items.count) stored item(s)")
        } catch {
            NSLog("Perch failed to load stored items: \(error)")
        }

        // Panel geometry is app-computed (a floating card), not user-movable, so we
        // always use the freshly computed frame rather than a stale persisted one.
        windowController.hide(animated: false)
        installEdgeStripIfNeeded()

        // During a drag, show only the tab nearest the cursor; hide all when it ends.
        mouseMonitor.onDragSessionChange = { [weak self] active in
            guard let self else { return }
            if active {
                self.showNearestTab(to: NSEvent.mouseLocation)
            } else {
                self.setTabsShown(false)
            }
        }
        mouseMonitor.onDragMoved = { [weak self] point in
            self?.showNearestTab(to: point)
        }
        mouseMonitor.start()

        // Resize the card to hug its contents on every change, and stay open while it
        // holds items / retract when empty. Subscribing fires immediately with the
        // loaded items.
        itemsCancellable = store.$items
            .sink { [weak self] items in
                self?.shelfItemsDidChange(items)
            }
    }

    /// React to the item list changing: run the open/retract logic only when the
    /// empty↔non-empty state actually flips. (Window resizing is driven separately by
    /// the SwiftUI content's measured height — see `contentHeightDidChange`.)
    private func shelfItemsDidChange(_ items: [StoredItem]) {
        let isEmpty = items.isEmpty
        guard isEmpty != wasEmpty else { return }
        wasEmpty = isEmpty
        shelfContentDidChange(isEmpty: isEmpty)
    }

    /// The SwiftUI content reported a new natural height — size the visible window to
    /// fit it exactly.
    private func contentHeightDidChange(_ height: CGFloat) {
        guard height > 0 else { return }
        measuredContentHeight = height
        guard panel.isVisible,
              let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        windowController.resize(to: Self.panelFrame(for: screen, edge: preferredEdge, contentHeight: height))
    }

    private func setTabsShown(_ shown: Bool) {
        for strip in edgeStrips {
            strip.showsTab = shown
        }
    }

    /// Show only the tab whose catch zone is nearest the cursor.
    private func showNearestTab(to point: NSPoint) {
        guard let nearest = edgeStrips.min(by: {
            Self.distance(from: point, to: $0.frame) < Self.distance(from: point, to: $1.frame)
        }) else {
            return
        }
        for strip in edgeStrips {
            strip.showsTab = (strip === nearest)
        }
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

    func pointerDidExitShelf() {
        exitRegion()
    }

    // MARK: EdgeStripDelegate

    func edgeStrip(_ strip: EdgeStripWindow, pointerDidEnterViaDrag viaDrag: Bool) {
        // Open the shelf on whichever screen + edge's tab was used.
        preferredScreen = strip.pinnedScreen
        preferredEdge = strip.edge
        // Drags open immediately; a plain hover waits briefly so brushing past the
        // edge does not pop the shelf open.
        enterRegion(immediate: viaDrag)
    }

    func edgeStripPointerDidExit(_ strip: EdgeStripWindow) {
        exitRegion()
    }

    /// Height of the "Drop here" empty state — also the card's minimum size.
    private static let emptyStateHeight: CGFloat = 100

    private static func initialPanelFrame() -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(x: 0, y: 0, width: 300, height: emptyStateHeight)
        }
        return panelFrame(for: screen, edge: .right, contentHeight: emptyStateHeight)
    }

    /// The card height that hugs `itemCount` rows (or the empty-state height when zero).
    private func contentHeight(for itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return Self.emptyStateHeight }
        let theme = themeStore.theme
        let rows = CGFloat(itemCount) * RowMetrics.height
            + CGFloat(itemCount - 1) * theme.rowSpacing
        return theme.contentPadding * 2 + rows
    }

    /// The content-hugging card frame on a screen + edge. Prefers the actual measured
    /// SwiftUI height; falls back to a per-item estimate before the first measurement.
    private func panelFrame(for screen: NSScreen, edge: ShelfEdge) -> NSRect {
        Self.panelFrame(
            for: screen,
            edge: edge,
            contentHeight: measuredContentHeight ?? contentHeight(for: store.items.count)
        )
    }

    /// The floating-card frame on a given screen + edge: inset from that edge so the
    /// edge tab's catch zone (wider than the margin) still overlaps the panel — no
    /// dead zone on the hand-off. Height tracks the content, capped to the screen.
    private static func panelFrame(for screen: NSScreen, edge: ShelfEdge, contentHeight: CGFloat) -> NSRect {
        let visibleFrame = screen.visibleFrame

        if edge == .notch {
            // A card hanging from the notch: centered on it, dropping down from just
            // below the menu bar.
            let width: CGFloat = 360
            let height = min(contentHeight, visibleFrame.height - 40)
            let interval = EdgeStripWindow.notchXInterval(for: screen)
            let centerX = (interval.min + interval.max) / 2
            let x = min(max(centerX - width / 2, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
            let y = visibleFrame.maxY - height
            return NSRect(x: x, y: y, width: width, height: height)
        }

        let margin: CGFloat = 12
        let width = min(CGFloat(300), visibleFrame.width - margin)
        // Grow freely to fit the contents; only the physical screen height bounds it.
        let height = min(contentHeight, visibleFrame.height - 24)
        let y = visibleFrame.minY + (visibleFrame.height - height) / 2
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
        for screen in Self.screensWithOuterEdge(.right) {
            strips.append(makeStrip(on: screen, edge: .right))
        }
        for screen in Self.screensWithOuterEdge(.left) {
            strips.append(makeStrip(on: screen, edge: .left))
        }
        for screen in NSScreen.screens where EdgeStripWindow.hasNotch(screen) {
            strips.append(makeStrip(on: screen, edge: .notch))
        }
        edgeStrips = strips
        NSLog("Perch installed \(strips.count) edge tab(s) across \(NSScreen.screens.count) screen(s)")
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

    /// The pointer left the region. The shelf stays open while it holds items;
    /// otherwise it retracts to the tab.
    private func exitRegion() {
        cancelOpen()
        pointerInRegion = false
        if store.items.isEmpty {
            scheduleRetract()
        }
    }

    /// Open and stay open while the shelf holds items; retract once empty (unless the
    /// pointer is hovering it).
    private func shelfContentDidChange(isEmpty: Bool) {
        if isEmpty {
            if !pointerInRegion {
                scheduleRetract()
            }
        } else {
            cancelRetract()
            revealIfNeeded()
        }
    }

    private func revealIfNeeded() {
        cancelRetract()
        guard !panel.isVisible else { return }

        let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        let frame = screen.map { panelFrame(for: $0, edge: preferredEdge) } ?? Self.initialPanelFrame()
        windowController.reveal(animated: true, targetFrame: frame, edge: preferredEdge)
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func cancelRetract() {
        retractTask?.cancel()
        retractTask = nil
    }

    /// Retract the shelf shortly after it should close. The small grace lets the
    /// pointer hand off between the edge tab and the panel without flicker; a
    /// re-enter (or new content) cancels it.
    private func scheduleRetract() {
        cancelRetract()
        retractTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard let self, !Task.isCancelled else { return }
            // Re-check: content may have arrived, or the pointer re-entered.
            guard self.store.items.isEmpty, !self.pointerInRegion else { return }
            self.windowController.hide(animated: true)
            self.retractTask = nil
        }
    }

    private func hideShelf(animated: Bool) {
        cancelRetract()
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
