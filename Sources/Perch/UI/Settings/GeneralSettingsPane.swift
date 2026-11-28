import AppKit
import SwiftUI

/// App-level controls that do not change how the shelf or files behave.
struct GeneralSettingsPane: View {
    private let loginItem = LoginItemController()
    @ObservedObject var smartPerch: SmartPerchCoordinator
    let clipboard: ClipboardCoordinator
    /// Unlocks Labs and brings its tab forward.
    let onRevealLabs: () -> Void
    let onShowWelcome: () -> Void
    let onReportProblem: () -> Void
    @ObservedObject var troubleshooting: TroubleshootingPresentation
    @State private var launchAtLogin = false
    @AppStorage(PerchSettings.showsMenuBarIcon) private var showsMenuBarIcon = true

    var body: some View {
        Form {
            Section {
                if loginItem.isAvailable {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                        .onAppear { launchAtLogin = loginItem.isEnabled }
                }
                Toggle("Show in menu bar", isOn: $showsMenuBarIcon)
            }

            ShortcutsSection()

            Section {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        Text("\(productName) \(appVersion)")
                        Button("Check for Updates") {
                            Updater.shared.checkForUpdates()
                        }
                    }
                }
                LabeledContent("Made by", value: "Max")
                    // The way into Labs: a triple click. Nothing about the row suggests it.
                    .contentShape(Rectangle())
                    .onTapGesture(count: 3, perform: onRevealLabs)
                HStack {
                    Button("Troubleshoot") { troubleshooting.isPresented = true }
                    Button("Run Setup Again", action: onShowWelcome)
                    Button("Restart Perch", action: Relauncher.restart)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $troubleshooting.isPresented) {
            TroubleshootingView(clipboard: clipboard, onReportProblem: onReportProblem)
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
        PerchProductIdentity.displayName(labsFeatureOn: smartPerch.isEnabled)
    }
}
