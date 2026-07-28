import SwiftUI

/// Settings for the optional, local Smart Perch features.
struct SmartPerchSettingsPane: View {
    @ObservedObject var smartPerch: SmartPerchCoordinator

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
                    Toggle("Smart Perch", isOn: smartPerchBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(smartPerch.isRemoving || smartPerch.isTransitioning)
                }
                .padding(.vertical, 2)
            }

            Section {
                Text("Smart Perch reads screenshots to name them and remembers where you usually put things. Everything stays in a local database on this Mac and is never sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Button("Remove Smart Perch and Delete Data", role: .destructive) {
                        showsUninstallConfirmation = true
                    }
                    .disabled(smartPerch.isRemoving || smartPerch.isTransitioning)
                    Text("Returns to regular Perch and permanently deletes everything Smart Perch learned. Shelf items are not affected.")
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
        .formStyle(.grouped)
        .alert("Remove Smart Perch?", isPresented: $showsUninstallConfirmation) {
            Button("Remove and Delete Data", role: .destructive) {
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
            : "Off — nothing you drop is analyzed or remembered."
    }

    private var smartPerchBinding: Binding<Bool> {
        Binding(
            get: { smartPerch.isEnabled },
            set: { smartPerch.setEnabled($0) }
        )
    }
}
