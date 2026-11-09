import AppKit
import SwiftUI

/// App-level controls that do not change how the shelf or files behave.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @ObservedObject var smartPerch: SmartPerchCoordinator
    /// Unlocks Labs and brings its tab forward.
    let onRevealLabs: () -> Void
    @State private var launchAtLogin = false
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
                    // The way into Labs: a triple click. Nothing about the row suggests it.
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3, perform: onRevealLabs)
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

    private var productName: String {
        PerchProductIdentity.displayName(labsFeatureOn: smartPerch.isEnabled)
    }
}
