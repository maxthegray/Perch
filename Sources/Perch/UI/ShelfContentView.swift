import SwiftUI

/// Reports the natural (intrinsic) height of the shelf's content so the window can size
/// itself to exactly fit — no clipping, no scrolling.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Centers one row stack in a lane that retains its 100%-size width when the card is
/// widened. The layout still occupies the card's full width, so the card background and
/// drop target keep their configured size while the entries gain breathing room.
private struct CenteredRowLaneLayout: Layout {
    let widthScale: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        guard let availableWidth = proposal.width else {
            return subview.sizeThatFits(proposal)
        }
        let laneWidth = RowMetrics.rowLaneWidth(
            availableWidth: availableWidth,
            widthScale: widthScale
        )
        let contentSize = subview.sizeThatFits(
            ProposedViewSize(width: laneWidth, height: nil)
        )
        return CGSize(width: availableWidth, height: contentSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let laneWidth = RowMetrics.rowLaneWidth(
            availableWidth: bounds.width,
            widthScale: widthScale
        )
        let contentSize = subview.sizeThatFits(
            ProposedViewSize(width: laneWidth, height: nil)
        )
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.minY),
            anchor: .top,
            proposal: ProposedViewSize(width: laneWidth, height: contentSize.height)
        )
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
    @ObservedObject var arrivals: RecentArrivals
    @ObservedObject var smartNames: SmartNameStore
    @ObservedObject var routeSuggestions: RouteSuggestionStore
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
            // The controller streams grabber reveal progress from the panel's live
            // resize, so hover itself must not add another implicit layout animation.
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
        // The lane grows by exactly the same amount as the AppKit window on every frame.
        // The content below therefore retains a constant height and screen position.
        let grabberProgress = min(max(interaction.grabberRevealProgress, 0), 1)
        let grabberHeight = RowMetrics.grabberZoneHeight * grabberProgress
        VStack(spacing: 0) {
            grabber
                .opacity(grabberProgress)
                .offset(y: (1 - grabberProgress) * 7)
                .frame(height: grabberHeight, alignment: .bottom)
                .clipped()
            if store.items.isEmpty {
                Group {
                    if ghostRows.isEmpty {
                        emptyState
                            .background(heightReader(addingGrabberStrip: grabberHeight))
                    } else if themeStore.stacksItems {
                        GeometryReader { proxy in
                            centeredRowLane {
                                stackedRowStack(
                                    availableWidth: proxy.size.width,
                                    availableHeight: proxy.size.height
                                )
                            }
                            .background(heightReader(addingGrabberStrip: grabberHeight))
                            .frame(maxHeight: .infinity)
                        }
                    } else {
                        // On an otherwise-empty shelf the offer *is* the shelf. Starting
                        // any system drag suppresses offers, swapping this straight back
                        // to the ordinary empty drop target before the drag reaches us.
                        centeredRowLane {
                            ghostStack
                                .padding(theme.contentPadding)
                        }
                        .background(heightReader(addingGrabberStrip: grabberHeight))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: ghostAnimationValue)
                .animation(nil, value: arrivals.suppressed)
                .frame(maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        centeredRowLane {
                            if themeStore.stacksItems {
                                stackedRowStack(
                                    availableWidth: proxy.size.width,
                                    availableHeight: proxy.size.height
                                )
                            } else {
                                rowStack(availableWidth: proxy.size.width)
                            }
                        }
                            .background(heightReader(addingGrabberStrip: grabberHeight))
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
            .filter { !interaction.vendingItemIDs.contains($0.id) }
    }

    /// Recent-arrival ghosts, hidden while a drag is in flight (`suppressed`) so they
    /// never shift the drop geometry under the cursor.
    private var ghostRows: [ArrivalGhost] {
        arrivals.suppressed ? [] : arrivals.visibleGhosts
    }

    /// Ghosts arriving and leaving animate; being suppressed for a drag does not — hence
    /// keying on the offers rather than on `ghostRows`. Suppression is a geometry freeze,
    /// and the shelf is usually *hidden* when it flips (a drag re-reveals a shelf whose
    /// ignored offers are still in the model): fading rows out over 0.18s inside a window
    /// that is fading in over 0.30s is what made the reveal look like it glitched.
    /// It is paired at every ghost site with `.animation(nil, value: arrivals.suppressed)`:
    /// the drag-start update also flips `isDropTarget`, and the card-level animation keyed
    /// on *that* would animate the rows away on suppression's behalf. A nil animation on
    /// this subtree overrides the ancestor for that one update.
    private var ghostAnimationValue: [ArrivalGhost] {
        arrivals.visibleGhosts
    }

    /// The dimmed recent-arrival rows. They follow real rows on a populated shelf and
    /// replace the drop tile when empty; AppKit hit-testing mirrors both placements.
    private var ghostStack: some View {
        VStack(alignment: .leading, spacing: theme.rowSpacing) {
            ForEach(ghostRows) { ghost in
                ArrivalGhostRowView(
                    ghost: ghost,
                    theme: theme,
                    isHovered: interaction.hoveredArrivalID == ghost.id,
                    showsLabels: themeStore.showsLabels,
                    smartName: smartNames.isEnabled
                        ? ghost.offer.flatMap { arrivals.smartName(for: $0) }
                        : nil,
                    usesScreenshotPlaceholder: smartNames.isEnabled
                )
                .transition(.opacity)
            }
        }
    }

    private func rowStack(availableWidth: CGFloat) -> some View {
        let maximumRowWidth = max(
            0,
            RowMetrics.rowLaneWidth(
                availableWidth: availableWidth,
                widthScale: rowLaneWidthScale
            ) - theme.contentPadding * 2
        )

        return VStack(alignment: .leading, spacing: theme.rowSpacing) {
            ForEach(displayedItems) { item in
                itemRow(
                    item,
                    showsSeparator: theme.usesRowSeparators && item.id != displayedItems.last?.id,
                    maximumWidth: maximumRowWidth
                )
            }
            if !ghostRows.isEmpty {
                ghostStack
            }
        }
        .animation(.easeOut(duration: 0.18), value: ghostAnimationValue)
        .animation(nil, value: arrivals.suppressed)
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

    /// A fanned deck that consumes the card's existing height. Later entries sit above
    /// earlier ones, leaving the leading edge of each card exposed so every item remains
    /// individually reachable without increasing the window height.
    private func stackedRowStack(
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        let itemCount = displayedItems.count
        let rowCount = itemCount + ghostRows.count
        let previewSide = RowMetrics.stackedPreviewSide(
            availableWidth: availableWidth,
            widthScale: themeStore.widthScale,
            availableHeight: availableHeight,
            contentPadding: theme.contentPadding
        )
        let pitch = RowMetrics.stackedRowPitch(
            availableHeight: availableHeight,
            rowCount: rowCount,
            rowHeight: previewSide,
            rowSpacing: theme.rowSpacing,
            contentPadding: theme.contentPadding
        )
        let contentHeight = RowMetrics.stackedContentHeight(
            rowCount: rowCount,
            rowHeight: previewSide,
            pitch: pitch,
            contentPadding: theme.contentPadding
        )

        return ZStack(alignment: .topLeading) {
            ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                stackedItemPreview(item, side: previewSide)
                    .offset(y: CGFloat(index) * pitch)
                    .zIndex(stackZIndex(for: item, index: index, rowCount: rowCount))
            }

            ForEach(Array(ghostRows.enumerated()), id: \.element.id) { index, ghost in
                stackedArrivalPreview(ghost, side: previewSide)
                    .offset(y: CGFloat(itemCount + index) * pitch)
                    .zIndex(Double(itemCount + index))
                    .transition(.opacity)
            }
        }
        .padding(theme.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: contentHeight, alignment: .top)
        .animation(.easeOut(duration: 0.18), value: ghostAnimationValue)
        .animation(nil, value: arrivals.suppressed)
        .animation(
            interaction.previewOrder != nil
                ? .spring(response: 0.34, dampingFraction: 0.86)
                : .easeOut(duration: 0.18),
            value: displayedItems.map(\.id)
        )
    }

    /// Deck mode is intentionally just the item's sample—no row material, border,
    /// separator, or label. The invisible square frame remains the interaction surface
    /// and keeps every preview aligned without adding visual chrome.
    private func stackedItemPreview(_ item: StoredItem, side: CGFloat) -> some View {
        let thumbnail = thumbnails.thumbnail(for: item, pointSize: side)
        return ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
            } else {
                Image(nsImage: item.iconImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side * 0.78, height: side * 0.78)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .scaleEffect(
            interaction.deletingItemIDs.contains(item.id) ? 1.06
                : (interaction.draggingItemID == item.id ? 1.035
                    : (interaction.hoveredItemID == item.id ? 1.02 : 1))
        )
        .opacity(interaction.draggingItemID == item.id ? 0.94 : 1)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeOut(duration: 0.14), value: interaction.hoveredItemID == item.id)
        .animation(.easeOut(duration: 0.18), value: thumbnail != nil)
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 0.8))
        ))
    }

    /// Arrival suggestions use the same chrome-free sample treatment, remaining dimmer
    /// than real perched items until adopted.
    private func stackedArrivalPreview(_ ghost: ArrivalGhost, side: CGFloat) -> some View {
        Group {
            switch ghost {
            case let .summary(session, _):
                ArrivalSessionStackIcon(session: session)
            case let .offer(offer, _):
                Image(nsImage: NSWorkspace.shared.icon(forFile: offer.url.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
            .frame(width: side * 0.78, height: side * 0.78)
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .scaleEffect(interaction.hoveredArrivalID == ghost.id ? 1.02 : 1)
            .opacity(interaction.hoveredArrivalID == ghost.id ? 0.8 : 0.48)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.14), value: interaction.hoveredArrivalID == ghost.id)
    }

    private func itemRow(
        _ item: StoredItem,
        showsSeparator: Bool,
        maximumWidth: CGFloat
    ) -> some View {
        let name = smartNames.presentation(
            for: item.id,
            originalTitle: item.metadata.title
        )
        return ItemRowView(
            item: item,
            theme: theme,
            isHovered: interaction.hoveredItemID == item.id,
            isSelected: interaction.selectedItemIDs.contains(item.id),
            isDragging: interaction.draggingItemID == item.id,
            isDeleting: interaction.deletingItemIDs.contains(item.id),
            thumbnail: thumbnails.thumbnail(for: item),
            showsSeparator: showsSeparator,
            showsLabels: themeStore.showsLabels,
            maximumWidth: maximumWidth,
            displayTitle: name.title,
            isNameAnalysisPending: name.isAnalyzing,
            learnedDestinationName: routeSuggestions.suggestion(for: item.id).map {
                RouteDestinationPresentation.shortName(for: $0.destination)
            }
        )
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .scale(scale: 0.8))
        ))
    }

    /// Keep the card being manipulated above the rest of the deck even when it was
    /// originally near the back.
    private func stackZIndex(for item: StoredItem, index: Int, rowCount: Int) -> Double {
        if interaction.draggingItemID == item.id || interaction.deletingItemIDs.contains(item.id) {
            return Double(rowCount + 1)
        }
        return Double(index)
    }

    /// Rows use the whole lane at 100% width. When the shelf is made wider (including
    /// the Square preset), the lane stays at that natural width and is centered so the
    /// added card area becomes an even margin on both sides.
    private func centeredRowLane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        CenteredRowLaneLayout(widthScale: rowLaneWidthScale) {
            content()
        }
    }

    /// A named, non-deck shelf already has a content-hugging window, so dividing its
    /// width by the Width slider again would recreate a narrow centered lane inside it.
    private var rowLaneWidthScale: CGFloat {
        !themeStore.stacksItems
            && themeStore.showsLabels
            && (!store.items.isEmpty || !ghostRows.isEmpty)
            ? 1
            : themeStore.widthScale
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
    private func heightReader(addingGrabberStrip grabberHeight: CGFloat = 0) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ContentHeightKey.self,
                value: proxy.size.height + grabberHeight
            )
        }
    }

    private var emptyState: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: RowMetrics.emptyTileHeight)
    }
}

/// A compact fan made from the batch's real file icons. Limiting the fan to three
/// keeps it legible at row size while the title communicates the complete count.
private struct ArrivalSessionStackIcon: View {
    let session: ArrivalSession

    private var displayedOffers: [ArrivalOffer] {
        Array(session.offers.prefix(3))
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let iconSide = side * 0.60
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                ForEach(Array(displayedOffers.enumerated()), id: \.element.id) { index, offer in
                    let spread = normalizedPosition(at: index)
                    Image(nsImage: NSWorkspace.shared.icon(forFile: offer.url.path))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSide, height: iconSide)
                        // An adaptive halo separates pale document icons without
                        // drawing a visible card or badge around each one.
                        .shadow(
                            color: Color(nsColor: .windowBackgroundColor).opacity(0.95),
                            radius: max(0.8, side * 0.04)
                        )
                        .rotationEffect(.degrees(spread * 24))
                        .offset(
                            x: spread * side * 0.40,
                            y: abs(spread) * side * 0.08
                        )
                        .shadow(
                            color: .black.opacity(0.24),
                            radius: max(0.5, side * 0.022),
                            y: max(0.5, side * 0.02)
                        )
                        .zIndex(layerDepth(at: index))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .position(center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// -0.5...0.5, centered for odd counts and evenly fanned for two.
    private func normalizedPosition(at index: Int) -> Double {
        guard displayedOffers.count > 1 else { return 0 }
        return Double(index) / Double(displayedOffers.count - 1) - 0.5
    }

    /// The centered file sits clearly on top; the two outer files remain visible
    /// behind it instead of one side washing over the middle.
    private func layerDepth(at index: Int) -> Double {
        let center = Double(displayedOffers.count - 1) / 2
        return Double(displayedOffers.count) - abs(Double(index) - center)
    }
}

/// A dimmed, dash-outlined row for a file that just landed in a watched folder: not
/// yet aboard, one tap away. Hover/click and context-menu plumbing is AppKit's
/// (`ShelfHostView`), same as the real rows.
struct ArrivalGhostRowView: View {
    let ghost: ArrivalGhost
    let theme: ShelfTheme
    let isHovered: Bool
    let showsLabels: Bool
    let smartName: String?
    /// With Smart Perch off, a screenshot ghost shows its real filename rather than the
    /// generic "Screenshot" label that stands in while a name is being generated.
    var usesScreenshotPlaceholder = true

    var body: some View {
        HStack(spacing: showsLabels ? RowMetrics.labeledRowSpacing : 0) {
            icon
                .frame(width: theme.iconSize, height: theme.iconSize)

            if showsLabels {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: theme.titleSize, weight: theme.titleWeight))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)

                    if theme.showsSubtitle {
                        Text(subtitle)
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    }
                }
            }
        }
        .padding(
            .horizontal,
            showsLabels ? RowMetrics.labeledRowHorizontalPadding : 0
        )
        .frame(
            maxWidth: .infinity,
            minHeight: theme.rowHeight,
            maxHeight: theme.rowHeight,
            alignment: showsLabels ? .leading : .center
        )
        .background(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .fill(isHovered ? theme.rowHoverFill : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(isHovered ? 0.22 : 0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                )
        )
        .contentShape(Rectangle())
        .opacity(isHovered ? 0.95 : (isSessionSummary ? 0.76 : 0.55))
        .animation(.easeOut(duration: 0.13), value: isHovered)
        .animation(.easeOut(duration: 0.18), value: title)
    }

    @ViewBuilder
    private var icon: some View {
        switch ghost {
        case let .summary(session, _):
            ArrivalSessionStackIcon(session: session)
        case let .offer(offer, _):
            Image(nsImage: NSWorkspace.shared.icon(forFile: offer.url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }

    private var title: String {
        ghost.displayTitle(
            smartName: smartName,
            usesScreenshotPlaceholder: usesScreenshotPlaceholder
        )
    }

    private var isSessionSummary: Bool {
        if case .summary = ghost { return true }
        return false
    }

    private var subtitle: String {
        let session = ghost.session
        let minutes = Int(-session.addedAt.timeIntervalSinceNow / 60)
        let age = minutes < 1 ? "Just now" : "\(minutes)m ago"
        switch ghost {
        case .summary(_, .expand):
            return "\(age) · \(session.locationName) · Click to add all"
        case .summary(_, .addAll):
            return "\(age) · \(session.locationName)"
        case let .offer(offer, _):
            return "\(age) · \(offer.locationName)"
        }
    }

}
