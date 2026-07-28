import AppKit
import SwiftUI

/// Tier one: what someone who just downloaded Perch needs and nothing else.
///
/// The bar for appearing here is that getting it wrong would surprise the user about what
/// happened to their files — which is really just drag-out's move-or-copy. Everything
/// else, including where the shelf docks, lives in Advanced, and the learning stack lives
/// further in still.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @State private var launchAtLogin = false
    @State private var versionClicks = 0
    @State private var showsUnlockConfirmation = false

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

            Section {
                LabeledContent("Version", value: appVersion)
                    // The way into Labs. Deliberately undiscoverable: nothing about the
                    // row suggests it, and the count resets whenever the pane goes away.
                    .contentShape(Rectangle())
                    .onTapGesture { registerVersionClick() }
                if showsUnlockConfirmation {
                    Text("Labs enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { versionClicks = 0 }
    }

    private func registerVersionClick() {
        guard !LabsAccess.isUnlocked else { return }
        versionClicks += 1
        guard versionClicks >= LabsAccess.unlockClickCount else { return }
        versionClicks = 0
        LabsAccess.unlock()
        showsUnlockConfirmation = true
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
}
