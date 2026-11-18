import AppKit
import SwiftUI

/// How the shelf looks and which places it can use.
struct ShelfSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var edgeSettings: EdgeSettings

    var body: some View {
        Form {
            Section {
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

                Toggle("Show item names", isOn: showsLabelsBinding)
                Toggle("Show shadow", isOn: $themeStore.showsShadow)
            }

            Section("Edges") {
                HStack(spacing: 8) {
                    locationToggle(
                        title: "Left",
                        symbol: "rectangle.leftthird.inset.filled",
                        isOn: edgeBinding(.left),
                        disabled: edgeIsLastEnabled(.left)
                    )

                    locationToggle(
                        title: "Notch",
                        symbol: "rectangle.topthird.inset.filled",
                        isOn: edgeBinding(.notch),
                        disabled: edgeIsLastEnabled(.notch)
                    )

                    locationToggle(
                        title: "Right",
                        symbol: "rectangle.rightthird.inset.filled",
                        isOn: edgeBinding(.right),
                        disabled: edgeIsLastEnabled(.right)
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private func edgeBinding(_ edge: ShelfEdge) -> Binding<Bool> {
        Binding(
            get: { edgeSettings.isEnabled(edge) },
            set: { _ in edgeSettings.toggle(edge) }
        )
    }

    private func edgeIsLastEnabled(_ edge: ShelfEdge) -> Bool {
        edgeSettings.isEnabled(edge) && edgeSettings.enabledEdges.count == 1
    }

    private func locationToggle(
        title: String,
        symbol: String,
        isOn: Binding<Bool>,
        disabled: Bool
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(disabled)
        .frame(maxWidth: .infinity)
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
}
