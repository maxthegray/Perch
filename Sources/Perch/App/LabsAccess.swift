import Foundation

/// Whether the Labs pane is available. Unlocking only reveals the pane; every feature in it
/// keeps its own switch and stays off until the user turns it on.
enum LabsAccess {
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: PerchSettings.labsUnlocked)
    }

    static func unlock() {
        guard !isUnlocked else { return }
        UserDefaults.standard.set(true, forKey: PerchSettings.labsUnlocked)
    }

    /// Every Labs switch outside Smart Perch, which has its own removal path.
    static let featureKeys = [
        PerchSettings.tripleClickToHide,
        PerchSettings.shakeToSummon,
        PerchSettings.moveOpenShelfBetweenEdges,
        PerchSettings.snapBesideDock,
        PerchSettings.showsEdgeTab,
        PerchSettings.referenceDroppedFiles
    ]

    /// Back to regular Perch: every Labs switch off and the tab hidden again.
    static func lock() {
        for key in featureKeys {
            UserDefaults.standard.set(false, forKey: key)
        }
        UserDefaults.standard.set(false, forKey: PerchSettings.labsUnlocked)
    }
}
