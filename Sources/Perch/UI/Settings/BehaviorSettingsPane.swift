import SwiftUI

/// When the shelf appears, how it moves, and when it stays open.
struct BehaviorSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore

    @AppStorage(PerchSettings.revealOnHover) private var revealOnHover = false
    @AppStorage(PerchSettings.revealOnDragStart) private var revealOnDragStart = true
    @AppStorage(PerchSettings.shelveOnEdgeTouch) private var shelveOnEdgeTouch = true
    @AppStorage(PerchSettings.keepEmptyShelf) private var keepEmptyShelf = true

    var body: some View {
        Form {
            Section("Show the shelf") {
                Toggle(isOn: $revealOnHover) {
                    Text("When the pointer touches an edge")
                    Text("When off, hold ⌃ Control or rest at the edge for 1.5 seconds.")
                }
                Toggle("When dragging files", isOn: $revealOnDragStart)
                Toggle(isOn: $themeStore.showsEdgeTab) {
                    Text("Edge reminder during long drags")
                    Text("Appears after five seconds of dragging.")
                }
            }

            Section {
                Toggle(isOn: $themeStore.showsGrabHandle) {
                    Text("Show a handle for moving the shelf")
                    Text("When off, hold ⌃ Control and drag the shelf.")
                }
                Toggle(isOn: $shelveOnEdgeTouch) {
                    Text("Hold at the edge to tuck away")
                    Text("Touch the edge again to bring it back.")
                }
                Toggle("Keep a floating shelf open when empty", isOn: $keepEmptyShelf)
            }
        }
        .formStyle(.grouped)
    }
}
