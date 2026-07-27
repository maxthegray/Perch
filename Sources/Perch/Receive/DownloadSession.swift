import Foundation
import SmartPerchCore

enum ArrivalLocation: String, Equatable, Sendable {
    case downloads
    case desktop

    var displayName: String {
        switch self {
        case .downloads: return "Downloads"
        case .desktop: return "Desktop"
        }
    }

    var supportsSessions: Bool {
        self == .downloads
    }
}

/// A file that recently landed in a watched folder, offered on the shelf as a dimmed
/// ghost until the user adopts or dismisses it.
struct ArrivalOffer: Identifiable, Equatable {
    let url: URL
    let addedAt: Date
    let location: ArrivalLocation
    /// Captured when the screenshot first appeared, before the desktop could change.
    let screenshotCaptureContext: ScreenshotCaptureContext?

    init(
        url: URL,
        addedAt: Date,
        location: ArrivalLocation,
        screenshotCaptureContext: ScreenshotCaptureContext? = nil
    ) {
        self.url = url
        self.addedAt = addedAt
        self.location = location
        self.screenshotCaptureContext = screenshotCaptureContext
    }

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var locationName: String { location.displayName }
}

/// Files that completed in the same Downloads burst. The UUID remains stable while
/// members are adopted or dismissed, and doubles as the Smart Perch drop batch ID.
struct ArrivalSession: Identifiable, Equatable {
    let id: UUID
    let offers: [ArrivalOffer]
    let totalFileCount: Int

    init(id: UUID, offers: [ArrivalOffer], totalFileCount: Int? = nil) {
        self.id = id
        self.offers = offers
        self.totalFileCount = max(totalFileCount ?? offers.count, offers.count)
    }

    var addedAt: Date {
        offers.map(\.addedAt).max() ?? .distantPast
    }

    var locationName: String {
        offers.first?.locationName ?? "Downloads"
    }

    var isBatch: Bool {
        offers.count > 1
    }
}

enum ArrivalSessionSummaryAction: Equatable {
    case expand
    case addAll
}

/// One rendered/hit-tested ghost row. A collapsed session contributes only its
/// summary; an expanded one contributes an Add All summary followed by member rows.
enum ArrivalGhost: Identifiable, Equatable {
    case summary(ArrivalSession, action: ArrivalSessionSummaryAction)
    case offer(ArrivalOffer, session: ArrivalSession)

    var id: String {
        switch self {
        case let .summary(session, _):
            return "session:\(session.id.uuidString)"
        case let .offer(offer, _):
            return "offer:\(offer.id)"
        }
    }

    var session: ArrivalSession {
        switch self {
        case let .summary(session, _), let .offer(_, session):
            return session
        }
    }

    var offer: ArrivalOffer? {
        if case let .offer(offer, _) = self {
            return offer
        }
        return nil
    }

    func displayTitle(smartName: String?) -> String {
        switch self {
        case let .summary(session, .expand):
            return "\(session.offers.count) new downloads"
        case let .summary(session, .addAll):
            return "Add all \(session.offers.count) downloads"
        case let .offer(offer, _):
            return smartName ?? offer.name
        }
    }
}

/// Pure temporal grouping used by the folder watcher. Desktop arrivals deliberately
/// remain singletons; only Downloads files can become a batch.
enum DownloadSessionGrouper {
    static let groupingWindow: TimeInterval = 5
    static let maximumFilesPerSession = 20

    static func group(
        _ offers: [ArrivalOffer],
        window: TimeInterval = groupingWindow
    ) -> [[ArrivalOffer]] {
        let sorted = offers.sorted {
            if $0.addedAt != $1.addedAt { return $0.addedAt > $1.addedAt }
            return $0.id < $1.id
        }

        var downloadGroups: [[ArrivalOffer]] = []
        for offer in sorted where offer.location.supportsSessions {
            if let newest = downloadGroups.last?.first,
               newest.addedAt.timeIntervalSince(offer.addedAt) <= window,
               downloadGroups[downloadGroups.count - 1].count < maximumFilesPerSession {
                downloadGroups[downloadGroups.count - 1].append(offer)
            } else {
                downloadGroups.append([offer])
            }
        }

        let desktopGroups = sorted
            .filter { !$0.location.supportsSessions }
            .map { [$0] }

        return (downloadGroups + desktopGroups).sorted {
            ($0.first?.addedAt ?? .distantPast) > ($1.first?.addedAt ?? .distantPast)
        }
    }
}
