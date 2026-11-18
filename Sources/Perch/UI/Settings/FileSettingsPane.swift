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
                Toggle(isOn: replacesOriginalBinding) {
                    Text("Replace the original after transforming")
                    Text("When off, the result appears beside the original.")
                }
                Toggle(isOn: $vendCopies) {
                    Text("Keep files in Perch after dragging them out")
                    if !vendCopies {
                        Text("When off, hold ⌥ Option to keep one.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var replacesOriginalBinding: Binding<Bool> {
        Binding(
            get: { transformOutputMode == .replace },
            set: { transformOutputMode = $0 ? .replace : .duplicate }
        )
    }
}
