import Foundation

enum PerchUpdateTrack: String {
    case standard
    case smart
}

struct UpdateTrackStore {
    static let selectionKey = "Perch.UpdateTrack"
    static let smartEnrollmentPendingKey = "Perch.SmartPerchEnrollmentPending"
    static let smartFeedURL = "https://raw.githubusercontent.com/maxthegray/Perch/smart-perch/appcast.xml"

    let defaults: UserDefaults
    let bundledTrack: PerchUpdateTrack

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        bundledTrack = (bundle.object(forInfoDictionaryKey: "PerchUpdateTrack") as? String)
            .flatMap(PerchUpdateTrack.init(rawValue:)) ?? .standard
    }

    init(defaults: UserDefaults, bundledTrack: PerchUpdateTrack) {
        self.defaults = defaults
        self.bundledTrack = bundledTrack
    }

    var selectedTrack: PerchUpdateTrack {
        defaults.string(forKey: Self.selectionKey)
            .flatMap(PerchUpdateTrack.init(rawValue:)) ?? bundledTrack
    }

    var feedURLString: String? {
        selectedTrack == .smart ? Self.smartFeedURL : nil
    }

    func enrollInSmartPerch() {
        defaults.set(PerchUpdateTrack.smart.rawValue, forKey: Self.selectionKey)
        defaults.set(true, forKey: Self.smartEnrollmentPendingKey)
    }
}
