import AppKit
import Foundation

/// Whether this launch is somebody's *first* launch, and what should happen if it is.
///
/// The distinction that matters is a new install versus an upgrade. Perch shipped for a
/// long time before it had a welcome window, so an install that has been in use since
/// 0.9 must not be greeted as though it were new: it already knows where the shelf
/// lives, and its Launch at Login state was decided — silently — by an older build.
/// Greeting it would also re-ask a question that install has effectively already
/// answered, and answering it "no" would unregister a login item the user never
/// complained about.
enum FirstRunExperience {
    enum Decision: Equatable {
        /// A genuinely new install: greet it, explain the gesture, and ask about Launch
        /// at Login before registering anything.
        case welcome
        /// An install that predates the welcome window. Mark first run done and leave
        /// every existing preference — Launch at Login included — exactly as it is.
        case adoptExistingInstall
        /// First run already happened.
        case none
    }

    /// Keys that only exist once Perch has actually been used: each is written by a
    /// deliberate user choice, or by the pre-1.0 launch-at-login default that ran on an
    /// old build's very first launch.
    ///
    /// Deliberately *excludes* keys like `sizePreset`, which `ThemeStore.init` writes on
    /// every install's first launch as a slider migration. Those are set before this
    /// question can be asked, so treating them as evidence of prior use would make every
    /// fresh install look like an upgrade and nobody would ever see the welcome window.
    static let usageMarkers = [
        PerchSettings.launchAtLoginDefaultApplied,
        PerchSettings.launchAtLoginUserChoice,
        PerchSettings.preferredShelfEdge,
        PerchSettings.vendCopies,
        PerchSettings.shelfStyle,
        PerchSettings.enabledEdges
    ]

    static func decide(hasCompletedFirstRun: Bool, hasUsageMarkers: Bool) -> Decision {
        if hasCompletedFirstRun { return .none }
        return hasUsageMarkers ? .adoptExistingInstall : .welcome
    }

    /// Read the decision from disk. Call this *before* anything that writes a default of
    /// its own — see `usageMarkers`.
    static func decide(defaults: UserDefaults = .standard) -> Decision {
        decide(
            hasCompletedFirstRun: defaults.bool(forKey: PerchSettings.firstRunCompleted),
            hasUsageMarkers: usageMarkers.contains {
                defaults.object(forKey: $0) != nil
            }
        )
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: PerchSettings.firstRunCompleted)
    }

    // MARK: - The edge picker

    /// The edges worth offering on this Mac, in the order they appear in the picker.
    ///
    /// The side docks always exist. The notch does not: offering it on a display without
    /// one would let the user choose an edge that installs no tab, leaving Perch looking
    /// broken at the spot they picked. `installEdgeStripIfNeeded` already skips notchless
    /// screens, so the picker simply agrees with it.
    static func offerableEdges(
        screens: [NSScreen] = NSScreen.screens
    ) -> [ShelfEdge] {
        var edges: [ShelfEdge] = [.left, .right]
        if screens.contains(where: EdgeStripWindow.hasNotch) {
            edges.append(.notch)
        }
        return edges
    }
}
