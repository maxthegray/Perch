import AppKit
import SwiftUI

/// App-level controls and the entry point for choosing the Settings layout.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @ObservedObject var smartPerch: SmartPerchCoordinator
    @State private var launchAtLogin = false
    @State private var versionClicks = 0
    @State private var showsSmartPerchPrompt = false

    @AppStorage(PerchSettings.settingsLayout)
    private var settingsLayout = SettingsLayout.beautiful
    @AppStorage(PerchSettings.vendCopies) private var vendCopies = false
    @AppStorage(PerchSettings.transformOutputMode)
    private var transformOutputMode = ShelfTransformOutputMode.duplicate

    var body: some View {
        Form {
            if loginItem.isAvailable {
                Section {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
            }

            Section("Settings") {
                Picker("Interface", selection: $settingsLayout) {
                    ForEach(SettingsLayout.allCases, id: \.rawValue) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
            }

            if settingsLayout == .ugly {
                Section("Drag out") {
                    HStack(alignment: .center, spacing: 12) {
                        BehaviorDemo(kind: .dragOut, flag: vendCopies)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Drag out")
                            Text(vendCopies
                                ? "Dragging an item out leaves it on the shelf."
                                : "Dragging an item out removes it from the shelf. "
                                    + "Hold Option to copy once.")
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

                Section("Transforms") {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Output")
                            Text(transformOutputMode == .duplicate
                                ? "Keep source rows and add transformed copies."
                                : "Remove source rows after their transforms succeed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Picker("Transform output", selection: $transformOutputMode) {
                            ForEach(ShelfTransformOutputMode.allCases, id: \.rawValue) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                LabeledContent("Version", value: "\(productName) \(appVersion)")
                    // The way into Smart Perch. Nothing about the
                    // row suggests it, and the count resets whenever the pane goes away.
                    .contentShape(Rectangle())
                    .onTapGesture { registerVersionClick() }
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { versionClicks = 0 }
        .alert("Enable Smart Perch?", isPresented: $showsSmartPerchPrompt) {
            Button("Enable Smart Perch") {
                smartPerch.setEnabled(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Smart Perch reads screenshots to suggest names and remembers where "
                    + "you put things. Everything stays on this Mac."
            )
        }
    }

    private func registerVersionClick() {
        guard !SmartPerchAccess.isUnlocked else { return }
        versionClicks += 1
        guard versionClicks >= SmartPerchAccess.unlockClickCount else { return }
        versionClicks = 0
        showsSmartPerchPrompt = true
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

    private var productName: String {
        smartPerch.isEnabled ? "Smart Perch" : "Perch"
    }
}
