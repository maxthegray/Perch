import Foundation

/// Where an item came from and what it is — the two facts route learning groups by.
///
/// For a recorded route this is copied from the item's original drop at insertion
/// time; for an item still sitting on the shelf it is read back out of that same drop
/// record, so a suggestion is matched against exactly the context that would have been
/// learned had the user dragged the item out by hand.
public struct RouteLearningContext: Equatable, Hashable, Sendable {
    public let sourceAppBundleIdentifier: String?
    public let sourceAppName: String?
    public let category: FileCategory?

    public init(
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        category: FileCategory?
    ) {
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.category = category
    }
}

/// The grouping identity shared by the detector and the matcher. Both sides must
/// derive it the same way, or a learned pattern would never match the item that
/// produced it.
struct LearningContextKey: Hashable {
    let sourceApplication: String
    let category: FileCategory?

    init(
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        category: FileCategory?
    ) {
        if let bundleIdentifier = sourceAppBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            sourceApplication = "bundle:\(bundleIdentifier.lowercased())"
        } else if let name = sourceAppName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty {
            sourceApplication = "name:\(name.lowercased())"
        } else {
            sourceApplication = "unknown"
        }
        self.category = category
    }

    init(route: ItemRouteEvent) {
        self.init(
            sourceAppBundleIdentifier: route.sourceAppBundleIdentifier,
            sourceAppName: route.sourceAppName,
            category: route.category
        )
    }

    init(pattern: LearnedRoutePattern) {
        self.init(
            sourceAppBundleIdentifier: pattern.sourceAppBundleIdentifier,
            sourceAppName: pattern.sourceAppName,
            category: pattern.category
        )
    }

    init(context: RouteLearningContext) {
        self.init(
            sourceAppBundleIdentifier: context.sourceAppBundleIdentifier,
            sourceAppName: context.sourceAppName,
            category: context.category
        )
    }
}
