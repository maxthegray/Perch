import Foundation

/// A route that has become sufficiently consistent to be useful to future UI and
/// automation policies. This milestone only exposes the value; it does not act on it.
public struct LearnedRoutePattern: Equatable, Sendable {
    public let sourceAppBundleIdentifier: String?
    public let sourceAppName: String?
    public let category: FileCategory?
    public let destination: RouteDestination
    public let occurrenceCount: Int
    public let contextSessionCount: Int
    public let destinationShare: Double

    public init(
        sourceAppBundleIdentifier: String?,
        sourceAppName: String?,
        category: FileCategory?,
        destination: RouteDestination,
        occurrenceCount: Int,
        contextSessionCount: Int,
        destinationShare: Double
    ) {
        self.sourceAppBundleIdentifier = sourceAppBundleIdentifier
        self.sourceAppName = sourceAppName
        self.category = category
        self.destination = destination
        self.occurrenceCount = occurrenceCount
        self.contextSessionCount = contextSessionCount
        self.destinationShare = destinationShare
    }
}

/// Conservative, deterministic route learning with no database or AppKit dependency.
public struct RoutePatternDetector: Sendable {
    public let minimumSessionCount: Int
    public let minimumDestinationShare: Double

    public init(
        minimumSessionCount: Int = 3,
        minimumDestinationShare: Double = 0.75
    ) {
        self.minimumSessionCount = minimumSessionCount
        self.minimumDestinationShare = minimumDestinationShare
    }

    public func detectPatterns(in routes: [ItemRouteEvent]) -> [LearnedRoutePattern] {
        guard minimumSessionCount > 0,
              minimumDestinationShare >= 0,
              minimumDestinationShare <= 1
        else {
            return []
        }

        let contexts = Dictionary(grouping: routes, by: LearningContextKey.init(route:))
        var patterns: [LearnedRoutePattern] = []

        for (context, contextRoutes) in contexts {
            let contextSessionCount = Set(contextRoutes.map(\.routeSessionID)).count
            guard contextSessionCount >= minimumSessionCount else { continue }

            let byDestination = Dictionary(
                grouping: contextRoutes,
                by: { $0.destination.normalizedIdentifier }
            )
            for destinationRoutes in byDestination.values {
                let occurrenceCount = Set(destinationRoutes.map(\.routeSessionID)).count
                guard occurrenceCount >= minimumSessionCount else { continue }

                let share = Double(occurrenceCount) / Double(contextSessionCount)
                guard share >= minimumDestinationShare,
                      let representative = destinationRoutes
                        .sorted(by: Self.routeOrder)
                        .last
                else {
                    continue
                }

                patterns.append(
                    LearnedRoutePattern(
                        sourceAppBundleIdentifier: representative.sourceAppBundleIdentifier,
                        sourceAppName: representative.sourceAppName,
                        category: context.category,
                        destination: representative.destination,
                        occurrenceCount: occurrenceCount,
                        contextSessionCount: contextSessionCount,
                        destinationShare: share
                    )
                )
            }
        }

        return patterns.sorted {
            if $0.destinationShare != $1.destinationShare {
                return $0.destinationShare > $1.destinationShare
            }
            if $0.occurrenceCount != $1.occurrenceCount {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.destination.normalizedIdentifier
                < $1.destination.normalizedIdentifier
        }
    }

    private static func routeOrder(_ lhs: ItemRouteEvent, _ rhs: ItemRouteEvent) -> Bool {
        if lhs.successfulDropAtMilliseconds != rhs.successfulDropAtMilliseconds {
            return lhs.successfulDropAtMilliseconds < rhs.successfulDropAtMilliseconds
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct LearningContextKey: Hashable {
    let sourceApplication: String
    let category: FileCategory?

    init(route: ItemRouteEvent) {
        if let bundleIdentifier = route.sourceAppBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleIdentifier.isEmpty {
            sourceApplication = "bundle:\(bundleIdentifier.lowercased())"
        } else if let name = route.sourceAppName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty {
            sourceApplication = "name:\(name.lowercased())"
        } else {
            sourceApplication = "unknown"
        }
        category = route.category
    }
}
