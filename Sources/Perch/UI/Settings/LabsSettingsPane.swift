import SwiftUI

/// Tier three: the experiments.
///
/// Everything here ships off and stays off unless the user goes looking. The captions are
/// deliberately blunt about what gets recorded — Perch's whole pitch is that it does not
/// watch you, so the one feature that does has to say so in plain words rather than
/// describe itself in terms of what it can do for you.
struct LabsSettingsPane: View {
    @ObservedObject var themeStore: ThemeStore

    @AppStorage(PerchSettings.smartPerchEnabled) private var smartPerchEnabled = false
    @AppStorage(PerchSettings.smartPerchShowsSuggestions) private var showsSuggestions = true
    @State private var showsUninstallConfirmation = false

    var body: some View {
        Form {
            Section("Smart Perch") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Perch")
                        Text(smartPerchCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Smart Perch", isOn: $smartPerchEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
                // Generated names are invisible on an icons-only shelf, so switching
                // Smart Perch on reveals the labels that show its work. This fires on
                // the transition only: "Show names" can be turned straight back off and
                // will stay off, and switching Smart Perch off never hides labels the
                // user asked for.
                .onChange(of: smartPerchEnabled) { _, enabled in
                    if enabled {
                        themeStore.showsLabels = true
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show suggestions")
                        Text("Turn this off to keep learning without showing suggestions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("Show suggestions", isOn: $showsSuggestions)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
                .disabled(!smartPerchEnabled)
            }

            Section {
                Text("Smart Perch reads screenshots to name them and remembers where you usually put things. Everything stays in a local database on this Mac and is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Uninstall Smart Perch", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    Text("Returns to regular Perch and permanently deletes everything Smart Perch learned. Shelf items are not affected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Uninstall Smart Perch?", isPresented: $showsUninstallConfirmation) {
            Button("Uninstall and Delete Data", role: .destructive) {
                Updater.shared.leaveSmartPerchAndDeleteData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This turns Smart Perch off, leaves its update track, and deletes its "
                    + "database from this Mac. Shelf items and regular Perch settings "
                    + "will not be affected."
            )
        }
    }

    /// Says what the switch actually does in each position. Off has to read as *nothing
    /// happens*, because that is now true: no database, no analysis, no history.
    private var smartPerchCaption: String {
        smartPerchEnabled
            ? "Names screenshots and remembers where you usually put things."
            : "Off — nothing you drop is analyzed or remembered."
    }
}
