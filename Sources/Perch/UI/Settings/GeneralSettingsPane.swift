import AppKit
import SwiftUI

/// Tier one: what someone who just downloaded Perch needs and nothing else.
///
/// The bar for appearing here is that leaving it out would either surprise the user
/// (drag-out changing whether their file survives) or leave the shelf unreachable (no
/// enabled edges). Everything else — how it looks, when it appears, how it moves — lives
/// in Advanced, and the learning stack lives further in still.
struct GeneralSettingsPane: View {
    @ObservedObject var edgeSettings: EdgeSettings

    private let loginItem = LoginItemController()
    @State private var launchAtLogin = false

    @AppStorage(PerchSettings.vendCopies) private var vendCopies = false

    var body: some View {
        Form {
            if loginItem.isAvailable {
                Section {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
            }

            Section("Drag out") {
                HStack(alignment: .center, spacing: 12) {
                    BehaviorDemo(kind: .dragOut, flag: vendCopies)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drag out")
                        Text(vendCopies
                            ? "Dragging an item out leaves it on the shelf."
                            : "Dragging an item out removes it from the shelf.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Picker("Drag out", selection: $vendCopies) {
                        Text("Move").tag(false)
                        Text("Copy").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }

            Section("Docking") {
                dockEdgeToggles
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Registration can fail (e.g. unbundled builds); revert the toggle to reality.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                launchAtLogin = loginItem.setEnabled(enabled) ? enabled : loginItem.isEnabled
            }
        )
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
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
}
