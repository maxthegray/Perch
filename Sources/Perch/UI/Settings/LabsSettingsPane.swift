import SwiftUI

/// Experimental features, each behind its own switch and off until turned on. Hidden
/// until unlocked from the General pane.
struct LabsSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var smartPerch: SmartPerchCoordinator
    /// Opens the read-only viewer for the database.
    let onShowData: () -> Void

    var body: some View {
        Form {
            ShelfExperimentsSection(themeStore: themeStore)
            SmartPerchSettingsSections(smartPerch: smartPerch, onShowData: onShowData)
            ReturnToRegularPerchSection(themeStore: themeStore, smartPerch: smartPerch)
        }
        .formStyle(.grouped)
    }
}

/// The one clear way out of Labs: delete Smart Perch's data, switch every experiment
/// off, and hide the tab until it is unlocked again.
struct ReturnToRegularPerchSection: View {
    @ObservedObject var themeStore: ThemeStore
    @ObservedObject var smartPerch: SmartPerchCoordinator

    @State private var confirming = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                confirming = true
            } label: {
                Text("Return to Regular Perch")
                Text("Turns off every Labs feature, deletes Smart Perch’s data, and hides Labs. Shelf items are not affected.")
            }
            .disabled(smartPerch.isRemoving || smartPerch.isTransitioning)
        }
        .alert("Return to regular Perch?", isPresented: $confirming) {
            Button("Turn Off and Delete", role: .destructive) {
                Task {
                    guard await smartPerch.removeData() else { return }
                    LabsAccess.lock()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Labs feature turns off and Smart Perch’s database is deleted from this Mac. Triple-click “Made by” in General to bring Labs back.")
        }
    }
}

/// Shelf gestures and placements that are still experiments.
struct ShelfExperimentsSection: View {
    @ObservedObject var themeStore: ThemeStore
    @AppStorage(PerchSettings.shakeToSummon) private var shakeToSummon = false
    @AppStorage(PerchSettings.moveOpenShelfBetweenEdges)
    private var moveOpenShelfBetweenEdges = false
    @AppStorage(PerchSettings.snapBesideDock) private var snapBesideDock = false
    @AppStorage(PerchSettings.referenceDroppedFiles) private var referenceDroppedFiles = false
    @AppStorage(PerchSettings.tripleClickToHide) private var tripleClickToHide = false

    var body: some View {
        Section("Shelf") {
            Toggle(isOn: $tripleClickToHide) {
                Text("Triple-click to hide the shelf")
                Text("Double-click Quick Look waits a moment in case a third click follows.")
            }
            Toggle(isOn: $shakeToSummon) {
                Text("Shake pointer to show")
                Text("Opens a floating shelf where the pointer is.")
            }
            Toggle(isOn: $moveOpenShelfBetweenEdges) {
                Text("Move an open shelf to the edge I touch")
                Text("Rest the pointer against another enabled edge.")
            }
            Toggle(isOn: $snapBesideDock) {
                Text("Snap beside the Dock")
                Text(dockCaption)
            }
            .onChange(of: snapBesideDock) { _, enabled in
                if enabled { DockGeometryReader.requestPermissionIfNeeded() }
            }
            Toggle(isOn: $referenceDroppedFiles) {
                Text("Leave dropped files where they are")
                Text("Perch links to them instead of moving them into its storage.")
            }
        }
    }

    private var dockCaption: String {
        if snapBesideDock, !DockGeometryReader.isTrusted {
            return "Needs Accessibility access in System Settings."
        }
        return "Adds both ends of the Dock as shelf locations."
    }
}

/// Perch Clipboard, the clipboard history.
struct ClipboardSettingsPane: View {
    @ObservedObject var clipboard: ClipboardCoordinator
    let onShowData: () -> Void

    var body: some View {
        Form {
            ClipboardSettingsSections(clipboard: clipboard, onShowData: onShowData)
        }
        .formStyle(.grouped)
    }
}

/// Settings for the optional, local Smart Perch features.
struct SmartPerchSettingsSections: View {
    @ObservedObject var smartPerch: SmartPerchCoordinator
    let onShowData: () -> Void

    @State private var showsUninstallConfirmation = false

    var body: some View {
        Group {
            Section {
                Toggle(isOn: smartPerchBinding) {
                    Text("Smart Perch")
                    Text(smartPerchCaption)
                }
                .disabled(smartPerch.isRemoving || smartPerch.isTransitioning)
            } header: {
                Text("Smart Perch")
            } footer: {
                Text("Everything stays in a local database on this Mac and is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("See Collected Data", action: onShowData)
                VStack(alignment: .leading, spacing: 4) {
                    Button("Delete Smart Perch Data", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    .disabled(smartPerch.isRemoving || smartPerch.isTransitioning)
                    Text("Turns Smart Perch off and deletes everything it learned. Shelf items are not affected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = smartPerch.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .alert("Delete Smart Perch’s data?", isPresented: $showsUninstallConfirmation) {
            Button("Delete Data", role: .destructive) {
                Task {
                    await smartPerch.removeData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This turns Smart Perch off and deletes its database from this Mac. "
                    + "Shelf items and regular Perch settings will not be affected."
            )
        }
    }

    /// Says what the switch actually does in each position. Off has to read as *nothing
    /// happens*, because that is now true: no database, no analysis, no history.
    private var smartPerchCaption: String {
        smartPerch.isEnabled
            ? "Names screenshots and remembers where you usually put things."
            : "Off. Nothing you drop is analyzed or remembered."
    }

    private var smartPerchBinding: Binding<Bool> {
        Binding(
            get: { smartPerch.isEnabled },
            set: { smartPerch.setEnabled($0) }
        )
    }
}
