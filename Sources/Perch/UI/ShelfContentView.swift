import SwiftUI

/// Reports the natural (intrinsic) height of the shelf's content so the window can size
/// itself to exactly fit — no clipping, no scrolling.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// SwiftUI list of stored items, hosted in the panel via `NSHostingView`. Rendered
/// as a translucent, rounded "card" whose look follows the active `ShelfStyle`. The
/// content is laid out at its intrinsic height and measured; `onContentHeight` lets the
/// controller grow/shrink the window to fit.
struct ShelfContentView: View {
    @ObservedObject var store: ItemStore
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var interaction: RowInteractionState
    @ObservedObject var thumbnails: ThumbnailStore
    @ObservedObject var ledger: ProvenanceLedger
    var onContentHeight: (CGFloat) -> Void = { _ in }

    private var theme: ShelfTheme { themeStore.theme }

    /// Landing "thunk" for the whole card: briefly squashed on stash, then springs back
    /// to rest. 1 at rest.
    @State private var thunkScale: CGFloat = 1

    /// The drag beacon's purple, matching the system accent family without following
    /// the user's accent (it must read as "Perch" from across the screen).
    private static let beaconPurple = Color(nsColor: .systemPurple)

    /// Drives the repeating inward pulse: flipped under a repeat-forever animation
    /// while a drag hovers the shelf, reset (without animation) when it leaves.
    @State private var beaconPulse = false

    /// The drag beacon, drawn just inside the card. While a system drag is anywhere on
    /// screen, a subtle purple outline + faint glow makes the shelf easy to spot. Once
    /// the drag is actually over the shelf it brightens, and a second ring repeatedly
    /// drifts inward toward the center — "it gets pulled in right here". (Inward, not
    /// outward: the window hugs the card exactly, so motion outside the card's bounds
    /// would clip at the window edge.)
    private var dragBeacon: some View {
        ZStack {
            beaconRing(
                inset: 0,
                lineWidth: interaction.isDragOverShelf ? 2 : 1.5,
                color: Self.beaconPurple.opacity(interaction.isDragOverShelf ? 0.85 : 0.4)
            )
                .shadow(
                    color: Self.beaconPurple.opacity(interaction.isDragOverShelf ? 0.5 : 0.3),
                    radius: interaction.isDragOverShelf ? 5 : 3
                )
            if interaction.isDragOverShelf {
                beaconRing(
                    inset: beaconPulse ? 8 : 0,
                    lineWidth: 1.5,
                    color: Self.beaconPurple
                )
                    .opacity(beaconPulse ? 0 : 0.55)
            }
        }
        .opacity(interaction.isDropTarget || interaction.isDragOverShelf ? 1 : 0)
        .clipShape(cardShape)
    }

    /// A ring drawn from the exact same insettable shape as the clipped card. This keeps
    /// the hover-intense outline and inward pulse on the card's real corner geometry.
    private func beaconRing(inset: CGFloat, lineWidth: CGFloat, color: Color) -> some View {
        cardShape
            .inset(by: inset)
            .strokeBorder(color, lineWidth: lineWidth)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        measuredContent
            // Center, not top: in a card floored taller than its content (the Height
            // slider), the rows/empty symbol sit in the middle and grow outward.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(theme.cardBackground)
            .clipShape(cardShape)
            .overlay(cardShape.stroke(theme.cardStrokeColor, lineWidth: theme.cardStrokeWidth))
            .overlay(dragBeacon)
            .animation(.easeInOut(duration: 0.22), value: themeStore.style)
            .animation(.easeInOut(duration: 0.2), value: themeStore.showsLabels)
            .animation(.easeInOut(duration: 0.2), value: themeStore.showsGrabHandle)
            // The bar also comes and goes with pinning (free mode) and Lock Position;
            // without these bindings its transition would cut in with no animation.
            .animation(.easeInOut(duration: 0.2), value: interaction.isFreeFloating)
            .animation(.easeInOut(duration: 0.2), value: interaction.isLockedInPlace)
            .animation(.easeOut(duration: 0.18), value: interaction.isDropTarget)
            .scaleEffect(thunkScale)
            .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
            .onChange(of: interaction.isDragOverShelf) { _, over in
                if over {
                    // Start the inward pulse. Reset + animate in one tick would collapse
                    // to no motion (same trick as the landing thunk below).
                    beaconPulse = false
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                            beaconPulse = true
                        }
                    }
                } else {
                    // Kill the repeat-forever without animating, so the next hover
                    // starts from a clean edge state.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { beaconPulse = false }
                }
            }
            .onChange(of: store.justAddedItemID) { _, id in
                guard id != nil else { return }
                // The whole card thunks on a stash: snap to a compressed state, then
                // spring back next tick (from/to in one tick would collapse to no motion).
                thunkScale = 0.78
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.5)) {
                        thunkScale = 1
                    }
                }
            }
    }

    /// The window sizes itself to the measured content height, so normally everything
    /// fits with no scrolling. The `ScrollView` is purely a safety net: if the list ever
    /// grows taller than the screen, the window caps and the overflow stays reachable
    /// instead of being clipped.
    @ViewBuilder
    private var measuredContent: some View {
        // The grab handle pins to the window's very top; the content (rows or the
        // empty tile) centers in the space below it. The row stack is centered within
        // the viewport (min-height frame), so on a floored-tall card each new row
        // grows the stack from the middle, nudging the earlier rows up by half a row.
        // The height reader stays attached to the bare content — the window must keep
        // sizing to its natural height, not the inflated frame — with the grabber
        // strip added back so the reported total still matches the controller's
        // estimate. The trailing animation eases the re-centering shift (the stack's
        // own animation only covers its subtree, not the position this outer frame
        // assigns it), matched to the rows' insert/remove ease. When the rows outgrow
        // the viewport the min-height is moot and the ScrollView scrolls as before.
        //
        // A free-floating card always carries the bar — even empty — unless locked in
        // place; docked cards follow the "Dragging Enabled" toggle and need rows. Must
        // mirror ShelfHostView.hasGrabber and the controller's height estimate.
        let showsGrabber = interaction.isFreeFloating
            ? !interaction.isLockedInPlace
            : (themeStore.showsGrabHandle && !displayedItems.isEmpty)
        VStack(spacing: 0) {
            if showsGrabber {
                grabber.transition(.opacity)
            }
            if store.items.isEmpty {
                emptyState
                    .background(heightReader(addingGrabberStrip: showsGrabber))
                    .frame(maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        rowStack
                            .background(heightReader(addingGrabberStrip: showsGrabber))
                            .frame(minHeight: proxy.size.height)
                            .animation(.easeOut(duration: 0.18), value: displayedItems.map(\.id))
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    /// Rows follow the live preview order while reordering, otherwise the store order.
    /// An item vended out in a move-mode drag is hidden — it's "in the cursor's hand" —
    /// and reappears here if the drag ends nowhere valid.
    private var displayedItems: [StoredItem] {
        (interaction.previewOrder ?? store.items)
            .filter { $0.id != interaction.vendingItemID }
    }

    /// An `origin → destination` provenance breadcrumb, using each path's parent folder
    /// name. Origin comes from the item's recorded source; destination from the latest
    /// ledger entry for the item. Returns nil when neither is known (falls back to the
    /// type subtitle).
    private func breadcrumb(for item: StoredItem) -> String? {
        let origin = item.metadata.originPaths?.values.first.map(locationLabel(forPath:))
        let destination = ledger.latestEntry(for: item.id).map { locationLabel(forPath: $0.destination) }
        switch (origin, destination) {
        case let (origin?, destination?): return "\(origin) → \(destination)"
        case let (origin?, nil): return "from \(origin)"
        case let (nil, destination?): return "→ \(destination)"
        case (nil, nil): return nil
        }
    }

    /// The parent folder name of a file path, for compact display.
    private func locationLabel(forPath path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let name = (parent as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    private var rowStack: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            ForEach(displayedItems) { item in
                ItemRowView(
                    item: item,
                    theme: theme,
                    isHovered: interaction.hoveredItemID == item.id,
                    isDragging: interaction.draggingItemID == item.id,
                    isDeleting: interaction.deletingItemID == item.id,
                    thumbnail: thumbnails.thumbnail(for: item),
                    showsSeparator: theme.usesRowSeparators && item.id != displayedItems.last?.id,
                    showsLabels: themeStore.showsLabels,
                    breadcrumb: breadcrumb(for: item)
                )
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.8))
                ))
            }
        }
        .padding(theme.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One transaction drives both the row fade and the layout: a spring while a
        // drag-to-reorder is in flight, a quick ease for inserts/removals. (A transition
        // carrying its own animation under a nil transaction — the previous setup —
        // flakily left surviving rows stuck invisible and fed bogus heights to the
        // window sizing.)
        .animation(
            interaction.previewOrder != nil
                ? .spring(response: 0.34, dampingFraction: 0.86)
                : .easeOut(duration: 0.18),
            value: displayedItems.map(\.id)
        )
    }

    /// A sheet-style grab handle pinned to the very top of the card, however tall it
    /// is: the one always-safe place to grab a populated card and move the whole thing
    /// (the rows themselves drag *items*). AppKit hit-testing treats this strip as card
    /// background, so a drag here becomes a whole-card move; the capsule brightens
    /// under the pointer to advertise it.
    private var grabber: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(interaction.isGrabberHovered ? 0.38 : 0.15))
            .frame(width: RowMetrics.grabberWidth, height: RowMetrics.grabberHeight)
            .scaleEffect(interaction.isGrabberHovered ? 1.12 : 1, anchor: .center)
            .frame(maxWidth: .infinity)
            .frame(height: RowMetrics.grabberZoneHeight)
            .animation(.easeOut(duration: 0.14), value: interaction.isGrabberHovered)
    }

    /// Reports the content's natural height up to the controller via a preference. The
    /// grab handle lives outside the measured row stack (pinned to the window top), so
    /// its strip is added back here — the reported total (grabber + padding + rows)
    /// must keep matching the controller's per-item estimate.
    private func heightReader(addingGrabberStrip: Bool = false) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ContentHeightKey.self,
                value: proxy.size.height + (addingGrabberStrip ? RowMetrics.grabberZoneHeight : 0)
            )
        }
    }

    private var emptyState: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
    }
}
