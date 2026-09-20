import AppKit
import SwiftUI

/// App-level controls that do not change how the shelf or files behave.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @ObservedObject var smartPerch: SmartPerchCoordinator
    @State private var launchAtLogin = false
    @State private var versionClicks = 0
    @State private var showsSmartPerchPrompt = false

    var body: some View {
        Form {
            if loginItem.isAvailable {
                Section("Startup") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
            }

            Section("About") {
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
