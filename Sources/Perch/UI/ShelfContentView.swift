import SwiftUI

/// SwiftUI list of stored items, hosted in the panel via `NSHostingView`.
struct ShelfContentView: View {
    @ObservedObject var store: ItemStore

    var body: some View {
        // TODO(T4): render the ordered list of `store.items` as `ItemRowView`s.
        EmptyView()
    }
}
