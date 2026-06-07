import SwiftUI

/// SwiftUI list of stored items, hosted in the panel via `NSHostingView`. Rendered
/// as a translucent, rounded "card" for a light, native feel.
struct ShelfContentView: View {
    @ObservedObject var store: ItemStore

    private var cardShape: RoundedRectangle {
        // Floating card (inset from the edge), so round all corners.
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(cardShape)
            .overlay(cardShape.stroke(.white.opacity(0.10), lineWidth: 0.5))
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.items) { item in
                        ItemRowView(item: item)
                    }
                }
                .padding(8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
