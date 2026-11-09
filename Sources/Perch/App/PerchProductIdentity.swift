enum PerchProductIdentity {
    /// "Perch Labs" while Smart Perch is on, so the app says so wherever it names itself.
    static var displayName: String {
        displayName(labsFeatureOn: SmartPerchSettings.isEnabled)
    }

    static func displayName(labsFeatureOn: Bool) -> String {
        labsFeatureOn ? "Perch Labs" : "Perch"
    }
}
