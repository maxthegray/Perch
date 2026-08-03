import AppKit
import SwiftUI

/// Tier two: how the shelf looks, when it appears, and how it moves.
///
/// One tab holding two short lists rather than one long scroll. The segmented switcher
/// keeps the outer tab bar compact while letting each half be seen at
/// once, and it tells the window which half is showing so the live preview shelf only
/// appears for Look — where there is actually something to preview.
struct AdvancedSettingsPane: View {
    enum Section: String, CaseIterable, Identifiable {
        case look = "Look"
        case behavior = "Behavior"
        case docking = "Docking"

        var id: String { rawValue }

        /// How tall the window should be for this section. Each list is a different
        /// length, and one shared height would mean either a wall of empty space under
        /// Look or Docking falling below the fold in Behavior.
        var preferredHeight: CGFloat {
            switch self {
            case .look: return 440
            case .behavior: return 820
            case .docking: return 380
            }
        }
    }

    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var edgeSettings: EdgeSettings
    var onSectionChanged: ((Section) -> Void)?

    @State private var section: Section = .look

    @AppStorage(PerchSettings.shakeToSummon) private var shakeToSummon = false
    @AppStorage(PerchSettings.revealOnDragStart) private var revealOnDragStart = true
    @AppStorage(PerchSettings.revealOnHover) private var revealOnHover = true
    @AppStorage(PerchSettings.keepEmptyShelf) private var keepEmptyShelf = true
    @AppStorage(PerchSettings.snapBesideDock) private var snapBesideDock = false
    @AppStorage(PerchSettings.offerRecentArrivals) private var offerRecentArrivals = true
    @AppStorage(PerchSettings.referenceDroppedFiles) private var referenceDroppedFiles = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch section {
            case .look: lookForm
            case .behavior: behaviorForm
            case .docking: dockingForm
            }
        }
        .onAppear { onSectionChanged?(section) }
        .onChange(of: section) { _, new in onSectionChanged?(new) }
    }

    // MARK: - Look

    private var lookForm: some View {
        Form {
            SwiftUI.Section("Layout") {
                Picker("Style", selection: $themeStore.style) {
                    ForEach(ShelfStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Items", selection: $themeStore.stacksItems) {
                    Text("List").tag(false)
                    Text("Stack").tag(true)
                }
                .pickerStyle(.segmented)

                Picker("Size", selection: $themeStore.sizePreset) {
                    ForEach(ShelfSizePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            }

            SwiftUI.Section("Details") {
                Toggle("Show names", isOn: showsLabelsBinding)
                Toggle("Shadow", isOn: $themeStore.showsShadow)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Edge tab while dragging", isOn: $themeStore.showsEdgeTab)
                    Text("The small handle that marks the shelf's dock during a drag. Dragging to the edge still reveals the shelf when it's off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Behavior

    private var behaviorForm: some View {
        Form {
            SwiftUI.Section("Showing the shelf") {
                behaviorRow(
                    demo: .revealOnHover,
                    title: "Auto-show on hover",
                    caption: "The shelf slides out when the pointer rests at its edge. Off leaves that edge alone until you drag something to it.",
                    isOn: $revealOnHover
                )
                behaviorRow(
                    demo: .revealOnDrag,
                    title: "Auto-show while dragging",
                    caption: "The shelf slides out when you start dragging a file.",
                    isOn: $revealOnDragStart
                )
                behaviorRow(
                    demo: .shakeToSummon,
                    title: "Shake to summon",
                    caption: "Shake the cursor to reveal the shelf.",
                    isOn: $shakeToSummon
                )
            }

            SwiftUI.Section("Floating shelf") {
                draggingModeRow
                behaviorRow(
                    demo: .keepEmpty,
                    flag: keepEmptyShelf,
                    title: "Keep open when empty",
                    caption: "The shelf stays out after its last item leaves.",
                    isOn: $keepEmptyShelf
                )
            }

            SwiftUI.Section("Recent downloads") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offer recent downloads")
                        Text("Files that just landed in Downloads or on the Desktop appear as dimmed rows — click one to bring it aboard.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Offer recent downloads", isOn: $offerRecentArrivals)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
            }

            SwiftUI.Section("File storage") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Leave dropped files in place")
                        Text("Perch keeps a pointer to each original file instead of moving it into its holding folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Leave dropped files in place", isOn: $referenceDroppedFiles)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Docking

    private var dockingForm: some View {
        Form {
            SwiftUI.Section("Edges") {
                dockEdgeToggles
            }

            SwiftUI.Section("Snapping") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beside the Dock")
                        Text(dockSnapCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Beside the Dock", isOn: $snapBesideDock)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
                .onChange(of: snapBesideDock) { _, enabled in
                    if enabled { DockGeometryReader.requestPermissionIfNeeded() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var dockSnapCaption: String {
        if snapBesideDock, !DockGeometryReader.isTrusted {
            return "Accessibility access is required; enable Perch in System Settings."
        }
        return "Adds both ends as snap points and follows the Dock when it hides."
    }

    private var showsLabelsBinding: Binding<Bool> {
        Binding(
            get: { themeStore.showsLabels },
            set: { showsNames in
                SmartPerchNamePreference.userChangedNames()
                themeStore.showsLabels = showsNames
            }
        )
    }

    /// One toggle per dockable edge. The last enabled edge is disabled rather than
    /// silently refused (EdgeSettings won't drop below one), so the constraint is visible.
    @ViewBuilder
    private var dockEdgeToggles: some View {
        let entries: [(String, ShelfEdge)] = [
            ("Left edge", .left), ("Right edge", .right), ("Top (Notch)", .notch)
        ]
        ForEach(entries, id: \.1) { title, edge in
            Toggle(title, isOn: Binding(
                get: { edgeSettings.isEnabled(edge) },
                set: { _ in edgeSettings.toggle(edge) }
            ))
            .disabled(edgeSettings.isEnabled(edge) && edgeSettings.enabledEdges.count == 1)
        }
    }

    private func behaviorRow(
        demo: BehaviorDemo.Kind,
        flag: Bool = true,
        title: String,
        caption: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            BehaviorDemo(kind: demo, flag: flag)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var draggingModeRow: some View {
        HStack(alignment: .center, spacing: 12) {
            BehaviorDemo(kind: .moveShelf)
            VStack(alignment: .leading, spacing: 2) {
                Text("Move shelf")
                Text(themeStore.showsGrabHandle
                    ? "Hover the shelf, then drag its handle."
                    : "Hold Command and drag anywhere on the shelf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("Move shelf using", selection: $themeStore.showsGrabHandle) {
                Text("Handle").tag(true)
                Text("⌘ + Click").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
}
