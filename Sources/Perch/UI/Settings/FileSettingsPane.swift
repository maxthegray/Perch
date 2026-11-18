import SwiftUI

/// What happens to files as they enter, change inside, and leave Perch.
struct FileSettingsPane: View {
    @AppStorage(PerchSettings.offerRecentArrivals)
    private var offerRecentArrivals = true
    @AppStorage(PerchSettings.transformOutputMode)
    private var transformOutputMode = ShelfTransformOutputMode.duplicate
    @AppStorage(PerchSettings.vendCopies)
    private var vendCopies = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $offerRecentArrivals) {
                    Text("Show recent arrivals")
                    Text("Offer new files from Downloads and the Desktop.")
                }
                Picker("After transforming a file", selection: $transformOutputMode) {
                    Text("Keep the original").tag(ShelfTransformOutputMode.duplicate)
                    Text("Replace the original").tag(ShelfTransformOutputMode.replace)
                }
                Picker(selection: $vendCopies) {
                    Text("Remove from Perch").tag(false)
                    Text("Keep in Perch").tag(true)
                } label: {
                    Text("After dragging a file out")
                    if !vendCopies {
                        Text("Hold ⌥ Option to keep it once.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
