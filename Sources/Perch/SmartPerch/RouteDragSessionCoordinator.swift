import AppKit
import SmartPerchCore

struct RouteDragItem: Equatable {
    let shelfItemID: UUID
    let addedToPerchAt: Date
    let expectsFilePromise: Bool
}

/// Merges file-promise completion and AppKit drag-ended evidence into one append-only
/// batch. A short asynchronous grace period lets an authoritative folder write beat
/// the less precise application-window observation.
@MainActor
final class RouteDragSessionCoordinator {
    typealias RecordRoutes = ([ItemRouteEvent]) -> Void

    private struct SuccessfulDrop {
        let occurredAt: Date
        let applicationDestination: RouteDestination?
    }

    let routeSessionID: UUID
    private let itemsByID: [UUID: RouteDragItem]
    private let transferMode: RouteTransferMode
    private let promiseGracePeriod: Duration
    private let recordRoutes: RecordRoutes
    private let onTerminal: ((UUID) -> Void)?

    private var successfulFoldersByItemID: [UUID: String] = [:]
    private var failedItemIDs: Set<UUID> = []
    private var successfulDrop: SuccessfulDrop?
    private var finalizationTask: Task<Void, Never>?
    private var isTerminal = false

    init(
        routeSessionID: UUID = UUID(),
        items: [RouteDragItem],
        transferMode: RouteTransferMode,
        promiseGracePeriod: Duration = .seconds(3),
        recordRoutes: @escaping RecordRoutes,
        onTerminal: ((UUID) -> Void)? = nil
    ) {
        precondition(!items.isEmpty)
        precondition(Set(items.map(\.shelfItemID)).count == items.count)
        self.routeSessionID = routeSessionID
        itemsByID = Dictionary(uniqueKeysWithValues: items.map {
            ($0.shelfItemID, $0)
        })
        self.transferMode = transferMode
        self.promiseGracePeriod = promiseGracePeriod
        self.recordRoutes = recordRoutes
        self.onTerminal = onTerminal
    }

    func filePromiseDidWrite(
        itemID: UUID,
        destinationFileURL: URL
    ) {
        guard !isTerminal, itemsByID[itemID] != nil else { return }
        failedItemIDs.remove(itemID)
        successfulFoldersByItemID[itemID] = destinationFileURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        finalizeIfAllPromisesResolved()
    }

    func filePromiseDidFail(itemID: UUID) {
        guard !isTerminal, itemsByID[itemID] != nil else { return }
        successfulFoldersByItemID.removeValue(forKey: itemID)
        failedItemIDs.insert(itemID)
        finalizeIfAllPromisesResolved()
    }

    /// Called exactly once from AppKit's drag-ended callback. Window inspection only
    /// happens for a successful external landing.
    func draggingEnded(
        operation: NSDragOperation,
        returnedToPerch: Bool,
        at screenPoint: NSPoint,
        occurredAt: Date = Date()
    ) {
        guard !isTerminal, successfulDrop == nil else { return }
        guard !operation.isEmpty, !returnedToPerch else {
            cancel()
            return
        }

        finishSuccessfulExternalDrop(
            applicationDestination: RouteDestinationResolver
                .application(atAppKitScreenPoint: screenPoint),
            occurredAt: occurredAt
        )
    }

    /// Split out for deterministic tests; production enters through `draggingEnded`.
    func finishSuccessfulExternalDrop(
        applicationDestination: RouteDestination?,
        occurredAt: Date
    ) {
        guard !isTerminal, successfulDrop == nil else { return }
        if let applicationDestination,
           case .folder = applicationDestination {
            successfulDrop = SuccessfulDrop(
                occurredAt: occurredAt,
                applicationDestination: nil
            )
        } else {
            successfulDrop = SuccessfulDrop(
                occurredAt: occurredAt,
                applicationDestination: applicationDestination
            )
        }

        if unresolvedPromiseItemIDs.isEmpty {
            finalize()
        } else {
            scheduleFinalization()
        }
    }

    func cancel() {
        guard !isTerminal else { return }
        isTerminal = true
        finalizationTask?.cancel()
        finalizationTask = nil
        successfulFoldersByItemID.removeAll()
        failedItemIDs.removeAll()
        onTerminal?(routeSessionID)
    }

    /// Forces the same resolution used when the production grace period expires.
    func finalizePendingRoutes() {
        finalize()
    }

    private var unresolvedPromiseItemIDs: Set<UUID> {
        Set(
            itemsByID.values
                .filter(\.expectsFilePromise)
                .map(\.shelfItemID)
        )
        .subtracting(successfulFoldersByItemID.keys)
        .subtracting(failedItemIDs)
    }

    private func finalizeIfAllPromisesResolved() {
        guard successfulDrop != nil, unresolvedPromiseItemIDs.isEmpty else { return }
        finalize()
    }

    private func scheduleFinalization() {
        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.promiseGracePeriod)
            guard !Task.isCancelled else { return }
            self.finalize()
        }
    }

    private func finalize() {
        guard !isTerminal, let successfulDrop else { return }
        isTerminal = true
        finalizationTask?.cancel()
        finalizationTask = nil

        let appFallback = nonFinderApplication(successfulDrop.applicationDestination)
        let dropMilliseconds = Int64(
            (successfulDrop.occurredAt.timeIntervalSince1970 * 1_000).rounded()
        )
        let routes = itemsByID.values
            .sorted { $0.shelfItemID.uuidString < $1.shelfItemID.uuidString }
            .compactMap { item -> ItemRouteEvent? in
                guard !failedItemIDs.contains(item.shelfItemID) else { return nil }

                let destination: RouteDestination
                let captureMethod: RouteCaptureMethod
                if let folder = successfulFoldersByItemID[item.shelfItemID] {
                    destination = .folder(path: folder)
                    captureMethod = .filePromiseWrite
                } else if let appFallback {
                    destination = appFallback
                    captureMethod = .applicationWindow
                } else {
                    return nil
                }

                let dwellMilliseconds = max(
                    0,
                    Int64(
                        (successfulDrop.occurredAt.timeIntervalSince(
                            item.addedToPerchAt
                        ) * 1_000).rounded()
                    )
                )
                return ItemRouteEvent(
                    routeSessionID: routeSessionID,
                    shelfItemID: item.shelfItemID,
                    successfulDropAtMilliseconds: dropMilliseconds,
                    dwellTimeMilliseconds: dwellMilliseconds,
                    destination: destination,
                    captureMethod: captureMethod,
                    transferMode: transferMode
                )
            }

        if !routes.isEmpty {
            recordRoutes(routes)
        }
        onTerminal?(routeSessionID)
    }

    private func nonFinderApplication(
        _ destination: RouteDestination?
    ) -> RouteDestination? {
        guard case let .application(bundleIdentifier, name) = destination else {
            return nil
        }
        let isFinder = bundleIdentifier?.caseInsensitiveCompare(
            "com.apple.finder"
        ) == .orderedSame || name.caseInsensitiveCompare("Finder") == .orderedSame
        return isFinder ? nil : destination
    }
}
