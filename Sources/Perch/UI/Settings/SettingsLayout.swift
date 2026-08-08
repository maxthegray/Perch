import Foundation

enum SettingsLayout: String, CaseIterable {
    case beautiful
    case ugly

    var displayName: String {
        switch self {
        case .beautiful: return "Beautiful"
        case .ugly: return "Ugly"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: PerchSettings.settingsLayout) else {
            return .beautiful
        }
        return Self(rawValue: rawValue) ?? .beautiful
    }
}
