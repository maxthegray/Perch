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

    var body: some View {
        Form {
            Section("smart perch") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("smart perch")
                        Text(smartPerchCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("smart perch", isOn: $smartPerchEnabled)
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
                        Text("show suggestions")
                        Text("turn this off if you want it to keep learning quietly.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Toggle("show suggestions", isOn: $showsSuggestions)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.vertical, 2)
                .disabled(!smartPerchEnabled)
            }

            Section {
                Text("it can read screenshots to name them and remember where you usually put things. everything stays in a little database on this mac. nothing gets sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button("hide smart perch") { hideLabs() }
                    Text("turns it off and tucks this tab away. it keeps what it already learned. click the version in general five times if you want it back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Off first, then hide. The other order would leave Smart Perch running behind a tab
    /// that no longer exists — and the launch migration would just unlock it again.
    private func hideLabs() {
        smartPerchEnabled = false
        LabsAccess.lock()
    }

    /// Says what the switch actually does in each position. Off has to read as *nothing
    /// happens*, because that is now true: no database, no analysis, no history.
    private var smartPerchCaption: String {
        smartPerchEnabled
            ? "on — i'll name screenshots and remember where you usually put things."
            : "off — i won't analyze or remember anything you drop."
    }
}
