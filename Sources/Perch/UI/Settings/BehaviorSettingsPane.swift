import SwiftUI

/// When the shelf appears, how it moves, and when it stays open.
struct BehaviorSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore

    @AppStorage(PerchSettings.revealOnHover) private var revealOnHover = true
    @AppStorage(PerchSettings.revealOnDragStart) private var revealOnDragStart = true
    @AppStorage(PerchSettings.shelveOnEdgeTouch) private var shelveOnEdgeTouch = true
    @AppStorage(PerchSettings.shakeToSummon) private var shakeToSummon = false
    @AppStorage(PerchSettings.keepEmptyShelf) private var keepEmptyShelf = true
    @AppStorage(PerchSettings.moveOpenShelfBetweenEdges)
    private var moveOpenShelfBetweenEdges = false

    var body: some View {
        Form {
            Section("Showing Perch") {
                settingToggle(
                    title: "Show when pointer touches an edge",
                    caption: "Rest the pointer at an enabled edge to reveal the shelf.",
                    isOn: $revealOnHover
                )
                settingToggle(
                    title: "Show when dragging files",
                    caption: "Reveal the shelf at the nearest enabled edge when a file drag starts.",
                    isOn: $revealOnDragStart
                )
                settingToggle(
                    title: "Show an edge reminder during long drags",
                    caption: "After five seconds of dragging, show where Perch is available.",
                    isOn: $themeStore.showsEdgeTab
                )
                settingToggle(
                    title: "Shake pointer to show",
                    caption: "Shake the pointer to open a floating shelf where it is.",
                    isOn: $shakeToSummon
                )
            }

            Section("Moving Perch") {
                moveShelfRow
                settingToggle(
                    title: "Move an open shelf to the edge I touch",
                    caption: "Rest the pointer against another enabled edge to move the shelf there.",
                    isOn: $moveOpenShelfBetweenEdges
                )
            }

            Section("Staying open") {
                settingToggle(
                    title: "Touch the current edge to hide or show Perch",
                    caption: "Rest the pointer against Perch’s edge to slide it away. Move away and touch that edge again to bring it back.",
                    isOn: $shelveOnEdgeTouch
                )
                settingToggle(
                    title: "Keep a floating shelf open when empty",
                    caption: "Leave a floating shelf visible after its last item is removed.",
                    isOn: $keepEmptyShelf
                )
            }
        }
        .formStyle(.grouped)
    }

    private func settingToggle(
        title: String,
        caption: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 2)
    }

    private var moveShelfRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Move the shelf using")
                Text(themeStore.showsGrabHandle
                    ? "Hover over the shelf, then drag its handle."
                    : "Hold Command and drag anywhere on the shelf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("Move the shelf using", selection: $themeStore.showsGrabHandle) {
                Text("Handle").tag(true)
                Text("Command-drag").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
