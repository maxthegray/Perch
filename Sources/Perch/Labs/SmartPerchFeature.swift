import AppKit
import Foundation
import SmartPerchCore
import SmartPerchVision
import UniformTypeIdentifiers

/// Everything Smart Perch does, behind one optional reference.
///
/// This exists so the master switch can be a real boundary rather than a filter on the
/// last step. All the machinery that costs something — the SQLite event log, the Vision
/// OCR worker, the per-arrival analysis tasks — is owned here, so when Smart Perch is off
/// the controller simply holds `nil` and none of it is ever constructed. That is what
/// makes "off" mean no database file, no OCR, and nothing recorded, instead of merely
/// hiding the results.
///
/// The two presentation stores stay on the controller rather than in here: they are inert
/// view-models that the SwiftUI content and the AppKit host bind to once at launch, and
/// rebuilding this object when the switch flips must not pull those bindings out from
/// under the view tree.
@MainActor
final class SmartPerchFeature {
    private let recorder: SmartPerchDropRecorder
    private let screenshotOCRWorker = ScreenshotOCRWorker()
    private let smartNames: SmartNameStore
    private let routeSuggestions: RouteSuggestionStore
    private let arrivals: RecentArrivals
    /// A read-only look at the shelf. Asynchronous work has to re-check what is still
    /// there when it lands, but this object has no business mutating the store — the
    /// controller performs every move and rename itself.
    private let currentItems: @MainActor () -> [StoredItem]

    private struct ArrivalNameAnalysis: Sendable {
        let ocrResult: ScreenshotOCRResult
        let suggestion: ScreenshotNameSuggestion?
    }

    /// Ghost analysis is transient: it improves the preview without creating a drop
    /// event. If adopted, the cached OCR result is transferred into the real log.
    private var arrivalNameAnalysisByPath: [String: ArrivalNameAnalysis] = [:]
    private var arrivalNameTasksByPath: [String: Task<Void, Never>] = [:]
    private var attemptedArrivalNamePaths: Set<String> = []

    /// Fails when the user has Smart Perch off, and when the event log cannot be opened —
    /// a damaged or unwritable log must never stop the shelf itself from launching and
    /// handling files, so the caller treats both the same way.
    init?(
        databaseURL: URL,
        smartNames: SmartNameStore,
        routeSuggestions: RouteSuggestionStore,
        arrivals: RecentArrivals,
        currentItems: @escaping @MainActor () -> [StoredItem]
    ) {
        guard SmartPerchSettings.isEnabled else { return nil }
        do {
            let eventStore = try SmartPerchEventStore(databaseURL: databaseURL)
            recorder = SmartPerchDropRecorder(eventStore: eventStore)
        } catch {
            NSLog("Perch could not open the Smart Perch event log: \(error)")
            return nil
        }
        self.smartNames = smartNames
        self.routeSuggestions = routeSuggestions
        self.arrivals = arrivals
        self.currentItems = currentItems
    }

    /// Drop in-flight analysis when the feature is being torn down (the user switched it
    /// off). The published stores are cleared by the controller, which owns them.
    func shutDown() {
        for task in arrivalNameTasksByPath.values {
            task.cancel()
        }
        arrivalNameTasksByPath.removeAll()
        arrivalNameAnalysisByPath.removeAll()
        attemptedArrivalNamePaths.removeAll()
    }

    // MARK: - Drops

    func recordDrop(
        _ item: StoredItem,
        context: DropRecordingContext,
        payloadKind: DropPayloadKind,
        screenshotCaptureContexts: [ScreenshotCaptureContext?]? = nil,
        prefetchedOCRResults: [ScreenshotOCRResult?]? = nil
    ) {
        let shelfItemID = item.id
        let fileURLs = item.backingFileURLs()
        let expectsSmartName = registerScreenshotPresentationIfNeeded(for: item)
        if expectsSmartName {
            smartNames.beginAnalyzingScreenshot(shelfItemID)
        }
        let capturedContexts = screenshotCaptureContexts ?? fileURLs.map {
            ScreenshotWindowContextCapture.captureFreshContext(for: $0)
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                if expectsSmartName {
                    smartNames.finishAnalyzingScreenshot(shelfItemID)
                }
            }
            do {
                let recordedDrop = try await recorder.recordFinalizedDrop(
                    context: context,
                    shelfItemID: shelfItemID,
                    payloadKind: payloadKind,
                    fileURLs: fileURLs,
                    screenshotCaptureContexts: capturedContexts
                )
                // The item's source app and category only become known to the log here,
                // so this is the first moment a learned route can be matched to it.
                self.refreshRouteSuggestions()
                await runPendingOCR(
                    in: recordedDrop,
                    fileURLs: fileURLs,
                    prefetchedOCRResults: prefetchedOCRResults
                )
            } catch {
                NSLog("Perch could not record Smart Perch drop \(context.eventID): \(error)")
            }
        }
    }

    func recordArrivalSessionInteraction(
        _ session: ArrivalSession,
        action: ArrivalSessionAction,
        affectedFileCount: Int
    ) {
        guard let location = session.offers.first?.location else { return }

        Task(priority: .utility) { [recorder] in
            do {
                try await recorder.recordArrivalSessionInteraction(
                    sessionID: session.id,
                    locationIdentifier: location.rawValue,
                    action: action,
                    totalFileCount: session.totalFileCount,
                    affectedFileCount: affectedFileCount
                )
            } catch {
                NSLog(
                    "Perch could not record arrival session \(session.id.uuidString): \(error)"
                )
            }
        }
    }

    // MARK: - Screenshot presentation

    /// Register screenshot presentation synchronously, before SwiftUI gets its first
    /// frame for a newly inserted row. Metadata is authoritative when available; the
    /// filename/type fallback covers a promise item whose file has only just arrived.
    @discardableResult
    func registerScreenshotPresentationIfNeeded(for item: StoredItem) -> Bool {
        let classifier = ExtensionHeuristicsClassifier()
        let gate = ScreenshotOCRGate()
        let isEligible = item.backingFileURLs().contains { url in
            guard let metadata = try? DroppedFileMetadata.capture(from: url) else {
                return false
            }
            return gate.isEligible(
                metadata,
                category: classifier.classify(metadata)
            )
        } || item.metadata.backingFileNames.contains { filename in
            guard ScreenshotNamePresentation.filenameLooksLikeScreenshot(filename),
                  let type = UTType(
                    filenameExtension: (filename as NSString).pathExtension
                  )
            else {
                return false
            }
            return type.conforms(to: .image)
        }

        if isEligible {
            smartNames.registerScreenshot(item.id)
        }
        return isEligible
    }

    func registerStoredScreenshotPresentations() {
        for item in currentItems() {
            registerScreenshotPresentationIfNeeded(for: item)
        }
    }

    // MARK: - Filename suggestions

    func loadFilenameSuggestions() {
        Task(priority: .utility) { [weak self, recorder] in
            do {
                let suggestions = try await recorder.prepareFilenameSuggestions()
                guard let self else { return }

                let itemsByID = Dictionary(uniqueKeysWithValues: currentItems().map {
                    ($0.id, $0)
                })
                var availableSuggestions: [AvailableFilenameSuggestion] = []
                var usedItemIDs: Set<UUID> = []
                for suggestion in suggestions {
                    guard let item = itemsByID[suggestion.shelfItemID],
                          item.metadata.backingFileNames == [suggestion.originalFilename],
                          usedItemIDs.insert(suggestion.shelfItemID).inserted
                    else {
                        continue
                    }
                    availableSuggestions.append(suggestion)
                }
                smartNames.replace(with: availableSuggestions)
            } catch {
                NSLog("Perch could not load Smart Perch filename suggestions: \(error)")
            }
        }
    }

    /// Identifies a rename the user has agreed to. The rename itself belongs to the
    /// controller — this object never touches the store — so accepting is two steps:
    /// check here, move the file there, then hand the outcome back to ``didAcceptRename``.
    struct AcceptedRename {
        let fileID: UUID
        let itemID: UUID
    }

    func plannedRename(
        of item: StoredItem,
        to proposedFilename: String
    ) -> AcceptedRename? {
        guard let suggestion = smartNames.suggestion(for: item.id),
              suggestion.suggestedFilename == proposedFilename,
              item.metadata.backingFileNames == [suggestion.originalFilename]
        else {
            return nil
        }
        return AcceptedRename(fileID: suggestion.fileID, itemID: item.id)
    }

    func didAcceptRename(_ rename: AcceptedRename, acceptedFilename: String) {
        smartNames.remove(for: rename.itemID)

        Task(priority: .utility) { [recorder] in
            do {
                try await recorder.acceptFilenameSuggestion(
                    fileID: rename.fileID,
                    acceptedFilename: acceptedFilename
                )
            } catch {
                NSLog(
                    "Perch could not record accepted filename suggestion for \(rename.itemID): \(error)"
                )
            }
        }
    }

    func dismissFilenameSuggestion(for item: StoredItem) {
        guard let suggestion = smartNames.remove(for: item.id) else { return }

        Task(priority: .utility) { [recorder] in
            do {
                try await recorder.dismissFilenameSuggestion(fileID: suggestion.fileID)
            } catch {
                NSLog(
                    "Perch could not record dismissed filename suggestion for \(item.id): \(error)"
                )
            }
        }
    }

    // MARK: - Learned routes

    /// Re-match the shelf against the learned routes. Cheap enough to run on every
    /// shelf change: it is one SQLite read plus a pure grouping pass, and it must react
    /// to items arriving, leaving, and to new evidence landing in the log.
    /// `items` must be supplied when called from a `store.$items` observer: `@Published`
    /// emits before `store.items` is replaced, so reading the property there would match
    /// against the shelf as it was a moment ago.
    func refreshRouteSuggestions(items: [StoredItem]? = nil) {
        let shelfItems = items ?? currentItems()
        let shelfItemIDs = shelfItems.map(\.id)
        guard !shelfItemIDs.isEmpty else {
            routeSuggestions.replace(with: [:])
            return
        }

        Task(priority: .utility) { [weak self, recorder] in
            do {
                let suggestions = try await recorder.fetchRouteSuggestions(
                    for: shelfItemIDs
                )
                guard let self else { return }
                // Items can leave while the read is in flight; never offer a route for
                // a row that is no longer there. By now the store has caught up, so its
                // own list is the authority.
                let liveItemIDs = Set(currentItems().map(\.id))
                routeSuggestions.replace(
                    with: suggestions.filter { liveItemIDs.contains($0.key) }
                )
            } catch {
                NSLog("Perch could not load learned route suggestions: \(error)")
            }
        }
    }

    func recordSuccessfulRoutes(_ routes: [ItemRouteEvent]) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await recorder.recordSuccessfulRoutes(routes)
            } catch {
                NSLog(
                    "Perch could not record route session \(routes.first?.routeSessionID.uuidString ?? "unknown"): \(error)"
                )
                return
            }
            // A drag just added evidence; the run it completes may be the one that makes
            // a route confident enough to offer for the items left behind.
            refreshRouteSuggestions()
        }
    }

    /// A learned route the user has asked to follow. Split the same way as a rename: the
    /// move is the controller's to perform, so it takes the folder from here and reports
    /// back whether anything actually left the shelf.
    struct RouteFiling {
        let itemID: UUID
        let folder: URL
        let destination: RouteDestination
        let addedToPerchAt: Date
    }

    func beginFilingAtSuggestedRoute(_ item: StoredItem) -> RouteFiling? {
        guard let suggestion = routeSuggestions.suggestion(for: item.id),
              let folder = RouteDestinationPresentation.folderURL(for: suggestion.destination)
        else {
            return nil
        }

        routeSuggestions.beginFiling(item.id)
        return RouteFiling(
            itemID: item.id,
            folder: folder,
            destination: suggestion.destination,
            addedToPerchAt: item.metadata.createdAt
        )
    }

    /// Nothing left the shelf — put the offer back rather than silently dropping it.
    func abandonFiling(_ filing: RouteFiling) {
        routeSuggestions.endFiling(filing.itemID)
        refreshRouteSuggestions()
    }

    /// Record the trip as an accepted suggestion so it enriches the history without
    /// feeding back into the pattern that produced it.
    func didFileAtSuggestedRoute(_ filing: RouteFiling) {
        let occurredAt = Date()
        let route = ItemRouteEvent(
            routeSessionID: UUID(),
            shelfItemID: filing.itemID,
            successfulDropAtMilliseconds: Int64(
                (occurredAt.timeIntervalSince1970 * 1_000).rounded()
            ),
            dwellTimeMilliseconds: max(
                0,
                Int64((occurredAt.timeIntervalSince(filing.addedToPerchAt) * 1_000).rounded())
            ),
            destination: filing.destination,
            captureMethod: .perchFiling,
            transferMode: .move,
            origin: .acceptedSuggestion
        )

        Task(priority: .utility) { [weak self, recorder] in
            do {
                try await recorder.recordSuccessfulRoutes([route])
            } catch {
                NSLog("Perch could not record filed route for \(filing.itemID): \(error)")
            }
            await MainActor.run { self?.routeSuggestions.endFiling(filing.itemID) }
        }
    }

    // MARK: - Shelf changes

    func itemsDidChange(_ items: [StoredItem], countChanged: Bool) {
        smartNames.retainPresentations(for: Set(items.map(\.id)))
        routeSuggestions.retainSuggestions(for: Set(items.map(\.id)))
        if countChanged {
            refreshRouteSuggestions(items: items)
        }
    }

    // MARK: - Arrival ghost names

    /// Precompute names only for screenshot offer rows the user can currently see.
    /// Vision remains on its serial utility queue; ordinary files and collapsed batch
    /// members never pay this cost.
    func prepareArrivalSmartNames() {
        let activePaths = Set(arrivals.sessions.flatMap(\.offers).map(\.id))
        let staleTaskPaths = arrivalNameTasksByPath.keys.filter {
            !activePaths.contains($0)
        }
        for path in staleTaskPaths {
            arrivalNameTasksByPath.removeValue(forKey: path)?.cancel()
        }
        arrivalNameAnalysisByPath = arrivalNameAnalysisByPath.filter {
            activePaths.contains($0.key)
        }
        attemptedArrivalNamePaths.formIntersection(activePaths)

        guard !arrivals.suppressed else { return }
        let visibleOffers = arrivals.visibleGhosts.compactMap(\.offer)
        for offer in visibleOffers
        where !attemptedArrivalNamePaths.contains(offer.id) {
            attemptedArrivalNamePaths.insert(offer.id)
            startArrivalNameAnalysis(for: offer)
        }
    }

    /// Hand over the cached OCR result for an offer being adopted, so the real drop
    /// record does not re-run Vision over a file that was already read for its preview.
    /// Any analysis still in flight for that path is cancelled: the row is about to
    /// become a real item, and the drop pipeline takes over from here.
    func takeArrivalAnalysis(forPath path: String) -> ScreenshotOCRResult? {
        arrivalNameTasksByPath.removeValue(forKey: path)?.cancel()
        return arrivalNameAnalysisByPath[path]?.ocrResult
    }

    private func startArrivalNameAnalysis(for offer: ArrivalOffer) {
        let path = offer.id
        let url = offer.url
        let captureContext = offer.screenshotCaptureContext
        let worker = screenshotOCRWorker

        arrivalNameTasksByPath[path] = Task.detached(priority: .utility) { [weak self] in
            let analysis: ArrivalNameAnalysis?
            do {
                let metadata = try DroppedFileMetadata.capture(from: url)
                let category = ExtensionHeuristicsClassifier().classify(metadata)
                guard ScreenshotOCRGate().isEligible(metadata, category: category),
                      !Task.isCancelled
                else {
                    await MainActor.run { [weak self] in
                        self?.arrivalNameTasksByPath[path] = nil
                    }
                    return
                }

                let result = try await worker.recognizeText(at: url)
                guard !Task.isCancelled else { return }
                let suggestion = ScreenshotFilenameSuggester().suggestName(
                    from: result.text ?? "",
                    recognizedLines: result.lines,
                    originalFilename: url.lastPathComponent,
                    screenshotCaptureContext: captureContext
                )
                analysis = ArrivalNameAnalysis(
                    ocrResult: result,
                    suggestion: suggestion
                )
            } catch {
                analysis = nil
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.arrivalNameTasksByPath[path] = nil
                guard self.arrivals.sessions.contains(where: { session in
                    session.offers.contains(where: { $0.id == path })
                }), let analysis
                else {
                    return
                }
                self.arrivalNameAnalysisByPath[path] = analysis
                if let suggestion = analysis.suggestion {
                    self.arrivals.setSmartName(
                        suggestion.displayName,
                        forPath: path
                    )
                }
                if analysis.ocrResult.durationMilliseconds > 2_000 {
                    NSLog(
                        "Perch screenshot ghost OCR took "
                            + "\(analysis.ocrResult.durationMilliseconds) ms for "
                            + "\(url.lastPathComponent)"
                    )
                }
            }
        }
    }

    // MARK: - OCR

    private func runPendingOCR(
        in drop: RecordedDrop,
        fileURLs: [URL],
        prefetchedOCRResults: [ScreenshotOCRResult?]? = nil
    ) async {
        for file in drop.files where file.ocrState == .pending {
            guard fileURLs.indices.contains(file.ordinal) else {
                try? await recorder.failOCR(fileID: file.fileID)
                continue
            }

            do {
                let result: ScreenshotOCRResult
                if let prefetchedOCRResults,
                   prefetchedOCRResults.indices.contains(file.ordinal),
                   let prefetched = prefetchedOCRResults[file.ordinal] {
                    result = prefetched
                } else {
                    result = try await screenshotOCRWorker.recognizeText(
                        at: fileURLs[file.ordinal]
                    )
                }
                let nameSuggestion = try await recorder.completeOCR(
                    fileID: file.fileID,
                    text: result.text,
                    recognizedLines: result.lines,
                    originalFilename: file.displayName,
                    durationMilliseconds: result.durationMilliseconds,
                    screenshotCaptureContext: file.screenshotCaptureContext
                )
                if let nameSuggestion {
                    smartNames.set(
                        AvailableFilenameSuggestion(
                            fileID: file.fileID,
                            shelfItemID: drop.event.shelfItemID,
                            originalFilename: file.displayName,
                            displayName: nameSuggestion.displayName,
                            suggestedFilename: nameSuggestion.suggestedFilename
                        )
                    )
                }
                if result.durationMilliseconds > 2_000 {
                    NSLog(
                        "Perch screenshot OCR took \(result.durationMilliseconds) ms for \(file.displayName)"
                    )
                }
            } catch {
                do {
                    try await recorder.failOCR(fileID: file.fileID)
                } catch {
                    NSLog("Perch could not persist failed OCR state for \(file.displayName): \(error)")
                }
            }
        }
    }
}
