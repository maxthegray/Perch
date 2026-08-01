import Foundation

/// Whether this launch should say what changed, and which notes it should show.
///
/// Perch has no Dock tile and no menu-bar item, so an update installs and relaunches with
/// nothing on screen to mark the occasion — the same silence that made the *first* launch
/// need a welcome window. This is the upgrade's version of that, and it follows the same
/// rule: appear once, say the useful thing, get out of the way.
enum WhatsNewExperience {
    enum Decision: Equatable {
        /// Show these notes, newest first.
        case show([ReleaseNote])
        case none
    }

    static func decide(
        currentVersion: SemanticVersion,
        lastSeenVersion: SemanticVersion?,
        notes: [ReleaseNote]
    ) -> Decision {
        guard let lastSeenVersion else {
            // No stamp at all: an install that predates this window. There is no way to
            // know what it has already seen, so show only what is new *now* rather than
            // greeting a long-time user with the entire history of the app.
            return announce(notes.filter { $0.version == currentVersion })
        }

        // A downgrade, or the same version relaunching. Nothing to announce either way.
        guard lastSeenVersion < currentVersion else { return .none }

        // Everything they skipped, not just the version they landed on: someone who
        // updates once a month should still learn what arrived in between.
        let unseen = notes
            .filter { $0.version > lastSeenVersion && $0.version <= currentVersion }
            .sorted { $0.version > $1.version }
        return announce(unseen)
    }

    /// Keeps only the releases that asked to be announced. A quiet release still has
    /// notes — in the appcast, on the release page, and in the bundle — it just does not
    /// open a window to deliver them. Someone catching up across several releases sees
    /// the notable ones alone rather than every fix in between.
    private static func announce(_ notes: [ReleaseNote]) -> Decision {
        let announced = notes.filter(\.announcesItself)
        return announced.isEmpty ? .none : .show(announced)
    }

    /// Read the decision from disk and the app bundle.
    static func decide(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        notes: [ReleaseNote]? = nil
    ) -> Decision {
        guard let currentVersion = SemanticVersion(bundleVersion(bundle)) else {
            // An unbundled build reports no usable version, so there is nothing to
            // compare against and nothing to stamp.
            return .none
        }
        return decide(
            currentVersion: currentVersion,
            lastSeenVersion: (defaults.string(forKey: PerchSettings.lastSeenVersion))
                .flatMap(SemanticVersion.init),
            notes: notes ?? ReleaseNotes.bundled(in: bundle)
        )
    }

    /// Record the running version as seen. Called whether or not anything was shown —
    /// including on a brand-new install, so the welcome window is never immediately
    /// followed by a What's New for the version that install started life on.
    static func markSeen(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        guard let version = SemanticVersion(bundleVersion(bundle)) else { return }
        defaults.set(version.description, forKey: PerchSettings.lastSeenVersion)
    }

    private static func bundleVersion(_ bundle: Bundle) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
