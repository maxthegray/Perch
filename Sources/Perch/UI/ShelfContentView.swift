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

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        measuredContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.cardMaterial)
            .clipShape(cardShape)
            .overlay(cardShape.stroke(theme.cardStrokeColor, lineWidth: theme.cardStrokeWidth))
            .animation(.easeInOut(duration: 0.22), value: themeStore.style)
            .animation(.easeInOut(duration: 0.2), value: themeStore.showsLabels)
            .animation(.easeOut(duration: 0.18), value: interaction.isDropTarget)
            .onPreferenceChange(ContentHeightKey.self) { onContentHeight($0) }
    }

    /// The window sizes itself to the measured content height, so normally everything
    /// fits with no scrolling. The `ScrollView` is purely a safety net: if the list ever
    /// grows taller than the screen, the window caps and the overflow stays reachable
    /// instead of being clipped.
    @ViewBuilder
    private var measuredContent: some View {
        if store.items.isEmpty {
            emptyState.background(heightReader)
        } else {
            ScrollView {
                rowStack.background(heightReader)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Rows follow the live preview order while reordering, otherwise the store order.
    private var displayedItems: [StoredItem] {
        interaction.previewOrder ?? store.items
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
                    thumbnail: thumbnails.thumbnail(for: item),
                    showsSeparator: theme.usesRowSeparators && item.id != displayedItems.last?.id,
                    showsLabels: themeStore.showsLabels,
                    breadcrumb: breadcrumb(for: item)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(theme.contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: displayedItems.map(\.id))
    }

    /// Reports the content's natural height up to the controller via a preference.
    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        }
    }

    private var emptyState: some View {
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: interaction.isDropTarget ? 28 : 22, weight: .light))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: interaction.isDropTarget ? 100 : 64)
    }
}
