enum PerchProductIdentity {
    static var displayName: String {
        SmartPerchSettings.isEnabled ? "Smart Perch" : "Perch"
    }
}
