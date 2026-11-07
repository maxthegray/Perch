import AppKit
import SwiftUI

/// App-level controls that do not change how the shelf or files behave.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @ObservedObject var smartPerch: SmartPerchCoordinator
    @State private var launchAtLogin = false
    @State private var showsSmartPerchPrompt = false
    @AppStorage(PerchSettings.showsMenuBarIcon) private var showsMenuBarIcon = true

    var body: some View {
        Form {
            if loginItem.isAvailable {
                Section("Startup") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
            }

            Section {
                Toggle(isOn: $showsMenuBarIcon) {
                    Text("Show in menu bar")
                    Text("Click to bring out the shelf, or drop files on it.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: "\(productName) \(appVersion)")
                LabeledContent("Made by", value: "Max")
                    // The way into Smart Perch. Nothing about the row suggests it.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !SmartPerchAccess.isUnlocked { showsSmartPerchPrompt = true }
                    }
                Button("Check for Updates…") {
                    Updater.shared.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
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
