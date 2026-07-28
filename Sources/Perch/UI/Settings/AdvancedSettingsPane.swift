import AppKit
import SwiftUI

/// Tier two: everything about how the shelf looks, when it appears, and how it moves.
///
/// This is the old Appearance and Behavior panes merged into one place. Every section is
/// named — the previous Behavior pane opened with three consecutive unlabelled groups,
/// which read as one undifferentiated wall of switches.
struct AdvancedSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore

    @AppStorage(PerchSettings.shakeToSummon) private var shakeToSummon = true
    @AppStorage(PerchSettings.revealOnDragStart) private var revealOnDragStart = true
    @AppStorage(PerchSettings.keepEmptyShelf) private var keepEmptyShelf = true
    @AppStorage(PerchSettings.snapBackToEdges) private var snapBackToEdges = true
    @AppStorage(PerchSettings.snapBesideDock) private var snapBesideDock = false
    @AppStorage(PerchSettings.offerRecentArrivals) private var offerRecentArrivals = true

    private enum SizePreset: CaseIterable {
        case standard, square, tall

        var name: String {
            switch self {
            case .standard: return "Standard"
            case .square: return "Square"
            case .tall: return "Tall"
            }
        }

        var previewSize: CGSize {
            switch self {
            case .standard: return CGSize(width: 34, height: 22)
            case .square: return CGSize(width: 34, height: 34)
            case .tall: return CGSize(width: 22, height: 40)
            }
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Style", selection: $themeStore.style) {
                    ForEach(ShelfStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show names", isOn: $themeStore.showsLabels)
                Toggle("Shadow", isOn: $themeStore.showsShadow)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Edge tab while dragging", isOn: $themeStore.showsEdgeTab)
                    Text("The small handle that marks the shelf's dock during a drag. Dragging to the edge still reveals the shelf when it's off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Size") {
                LabeledContent("Presets") {
                    HStack(spacing: 8) {
                        ForEach(SizePreset.allCases, id: \.self) { preset in
                            presetButton(preset)
                        }
                    }
                }

                LabeledContent("Width") {
                    Slider(value: widthScaleBinding, in: ThemeStore.widthScaleRange)
                }

                LabeledContent("Height") {
                    Slider(value: heightFractionBinding, in: ThemeStore.heightFractionRange)
                }

                Toggle("Stack items instead of growing", isOn: $themeStore.stacksItems)
            }

            Section("Behavior") {
                behaviorRow(
                    demo: .shakeToSummon,
                    title: "Shake to summon",
                    caption: "Shake the cursor to reveal the shelf.",
                    isOn: $shakeToSummon
                )
                behaviorRow(
                    demo: .revealOnDrag,
                    title: "Auto-show while dragging",
                    caption: "The shelf slides out when you start dragging a file.",
                    isOn: $revealOnDragStart
                )
                behaviorRow(
                    demo: .keepEmpty,
                    flag: keepEmptyShelf,
                    title: "Keep open when empty",
                    caption: "The shelf stays out after its last item leaves.",
                    isOn: $keepEmptyShelf
                )
                draggingModeRow
                behaviorRow(
                    demo: .moveShelf,
                    title: "Snap to locations",
                    caption: "Release a free shelf near an enabled screen edge or Dock side.",
                    isOn: $snapBackToEdges
                )

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

            Section("Docking") {
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

    private func presetButton(_ preset: SizePreset) -> some View {
        let selected = isSelected(preset)
        return Button {
            let values = values(for: preset)
            themeStore.widthScale = values.width
            themeStore.heightFraction = values.height
            themeStore.squarePresetSelected = preset == .square
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.45))
                    }
                    .frame(width: preset.previewSize.width, height: preset.previewSize.height)
                    .frame(height: 40)
                Text(preset.name)
                    .font(.caption)
            }
            .frame(width: 58)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25))
        }
        .accessibilityLabel("\(preset.name) size")
    }

    private func isSelected(_ preset: SizePreset) -> Bool {
        let values = values(for: preset)
        return abs(themeStore.widthScale - values.width) < 0.001
            && abs(themeStore.heightFraction - values.height) < 0.001
            && themeStore.squarePresetSelected == (preset == .square)
    }

    private func values(for preset: SizePreset) -> (width: CGFloat, height: CGFloat) {
        switch preset {
        case .standard:
            return (1, 0)
        case .square:
            // The empty Appearance preview is 80 points wide at the standard scale.
            // At 150% the preset is therefore 120 points wide; convert that matching
            // height into the slider's screen-relative unit so it renders as a square.
            let usableHeight = max(1, (NSScreen.main?.visibleFrame.height ?? 924) - 24)
            return (1.5, min(120 / usableHeight, 1))
        case .tall:
            return (1, 0.8)
        }
    }

    /// Detent at the design width: close enough to 100% snaps the thumb and the value.
    private var widthScaleBinding: Binding<CGFloat> {
        Binding(
            get: { themeStore.widthScale },
            set: {
                themeStore.squarePresetSelected = false
                themeStore.widthScale = abs($0 - 1) < 0.04 ? 1 : $0
            }
        )
    }

    private var heightFractionBinding: Binding<CGFloat> {
        Binding(
            get: { themeStore.heightFraction },
            set: {
                themeStore.squarePresetSelected = false
                themeStore.heightFraction = $0
            }
        )
    }
}
