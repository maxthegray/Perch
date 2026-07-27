import Foundation

/// Finalizes drop records away from the UI actor.
public actor SmartPerchDropRecorder {
    private let eventStore: SmartPerchEventStore
    private let classifier: ExtensionHeuristicsClassifier
    private let screenshotOCRGate: ScreenshotOCRGate
    private let filenameSuggester: ScreenshotFilenameSuggester

    public init(
        eventStore: SmartPerchEventStore,
        classifier: ExtensionHeuristicsClassifier = ExtensionHeuristicsClassifier(),
        screenshotOCRGate: ScreenshotOCRGate = ScreenshotOCRGate(),
        filenameSuggester: ScreenshotFilenameSuggester = ScreenshotFilenameSuggester()
    ) {
        self.eventStore = eventStore
        self.classifier = classifier
        self.screenshotOCRGate = screenshotOCRGate
        self.filenameSuggester = filenameSuggester
    }

    @discardableResult
    public func recordFinalizedDrop(
        context: DropRecordingContext,
        shelfItemID: UUID,
        payloadKind: DropPayloadKind,
        fileURLs: [URL],
        screenshotCaptureContexts: [ScreenshotCaptureContext?] = []
    ) throws -> RecordedDrop {
        let event = DropEvent(
            id: context.eventID,
            batchID: context.batchID,
            shelfItemID: shelfItemID,
            occurredAtMilliseconds: Int64(
                (context.occurredAt.timeIntervalSince1970 * 1_000).rounded()
            ),
            sourceAppBundleIdentifier: context.sourceApplication?.bundleIdentifier,
            sourceAppName: context.sourceApplication?.displayName,
            payloadKind: payloadKind
        )

        let files = fileURLs.enumerated().map { ordinal, url in
            let metadata = (try? DroppedFileMetadata.capture(from: url))
                ?? DroppedFileMetadata(url: url)
            let category = classifier.classify(metadata)
            let ocrState: OCRProcessingState = screenshotOCRGate.isEligible(
                metadata,
                category: category
            ) ? .pending : .notEligible
            let screenshotContext = screenshotCaptureContexts.indices.contains(ordinal)
                ? screenshotCaptureContexts[ordinal]
                : nil
            let screenshotContextJSON = screenshotContext
                .flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            return DroppedFileEvent(
                fileID: UUID(),
                dropEventID: event.id,
                ordinal: ordinal,
                displayName: url.lastPathComponent,
                pathExtension: url.pathExtension.lowercased(),
                contentTypeIdentifier: metadata.contentTypeIdentifier,
                byteCount: metadata.byteCount,
                isDirectory: metadata.isDirectory,
                isScreenCapture: metadata.isScreenCapture,
                category: category,
                classifierIdentifier: ExtensionHeuristicsClassifier.identifier,
                classifierVersion: ExtensionHeuristicsClassifier.version,
                ocrState: ocrState,
                ocrText: nil,
                ocrCompletedAtMilliseconds: nil,
                ocrDurationMilliseconds: nil,
                screenshotCaptureContextJSON: screenshotContextJSON
            )
        }

        try eventStore.record(event, files: files)
        return RecordedDrop(event: event, files: files)
    }

    @discardableResult
    public func completeOCR(
        fileID: UUID,
        text: String?,
        recognizedLines: [RecognizedTextLine] = [],
        originalFilename: String,
        durationMilliseconds: Int64,
        screenshotCaptureContext: ScreenshotCaptureContext? = nil
    ) throws -> ScreenshotNameSuggestion? {
        let normalizedText = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let state: OCRProcessingState = normalizedText?.isEmpty == false
            ? .completed
            : .noText
        let nameSuggestion = filenameSuggester.suggestName(
            from: normalizedText ?? "",
            recognizedLines: recognizedLines,
            originalFilename: originalFilename,
            screenshotCaptureContext: screenshotCaptureContext
        )
        let ocrLayoutJSON = recognizedLines.isEmpty
            ? nil
            : try? String(
                data: JSONEncoder().encode(recognizedLines),
                encoding: .utf8
            )

        try eventStore.finishOCR(
            fileID: fileID,
            state: state,
            text: state == .completed ? normalizedText : nil,
            completedAtMilliseconds: Self.currentMilliseconds(),
            durationMilliseconds: durationMilliseconds,
            ocrLayoutJSON: ocrLayoutJSON,
            smartLabel: nameSuggestion?.displayName,
            filenameSuggestion: nameSuggestion?.suggestedFilename,
            filenameSuggesterIdentifier: ScreenshotFilenameSuggester.identifier,
            filenameSuggesterVersion: ScreenshotFilenameSuggester.version
        )
        return nameSuggestion
    }

    public func failOCR(fileID: UUID) throws {
        try eventStore.finishOCR(
            fileID: fileID,
            state: .failed,
            text: nil,
            completedAtMilliseconds: Self.currentMilliseconds(),
            durationMilliseconds: nil,
            filenameSuggesterIdentifier: ScreenshotFilenameSuggester.identifier,
            filenameSuggesterVersion: ScreenshotFilenameSuggester.version
        )
    }

    public func fetchAllDrops() throws -> [RecordedDrop] {
        try eventStore.fetchAllDrops()
    }

    /// Backfill suggestions from already-persisted OCR text after the suggestion
    /// columns first ship. Vision is not rerun.
    public func prepareFilenameSuggestions() throws -> [AvailableFilenameSuggestion] {
        var drops = try eventStore.fetchAllDrops()

        for drop in drops {
            for file in drop.files
            where (file.ocrState == .completed
                    || (file.ocrState == .noText
                        && file.screenshotCaptureContext != nil))
                && (file.filenameSuggestionState == .notEvaluated
                    || (file.filenameSuggestionState == .available
                        && (file.smartLabel == nil
                            || file.filenameSuggesterVersion
                                != ScreenshotFilenameSuggester.version))) {
                let recognizedLines = file.ocrLayoutJSON
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap {
                        try? JSONDecoder().decode(
                            [RecognizedTextLine].self,
                            from: $0
                        )
                    } ?? []
                let suggestion = filenameSuggester.suggestName(
                    from: file.ocrText ?? "",
                    recognizedLines: recognizedLines,
                    originalFilename: file.displayName,
                    screenshotCaptureContext: file.screenshotCaptureContext
                )
                try eventStore.storeFilenameSuggestionEvaluation(
                    fileID: file.fileID,
                    smartLabel: suggestion?.displayName,
                    filenameSuggestion: suggestion?.suggestedFilename,
                    filenameSuggesterIdentifier: ScreenshotFilenameSuggester.identifier,
                    filenameSuggesterVersion: ScreenshotFilenameSuggester.version
                )
            }
        }

        drops = try eventStore.fetchAllDrops()
        return Self.availableFilenameSuggestions(in: drops)
    }

    public func acceptFilenameSuggestion(
        fileID: UUID,
        acceptedFilename: String
    ) throws {
        try eventStore.resolveFilenameSuggestion(
            fileID: fileID,
            state: .accepted,
            acceptedFilename: acceptedFilename,
            decidedAtMilliseconds: Self.currentMilliseconds()
        )
    }

    public func dismissFilenameSuggestion(fileID: UUID) throws {
        try eventStore.resolveFilenameSuggestion(
            fileID: fileID,
            state: .dismissed,
            acceptedFilename: nil,
            decidedAtMilliseconds: Self.currentMilliseconds()
        )
    }

    public func recordArrivalSessionInteraction(
        sessionID: UUID,
        locationIdentifier: String,
        action: ArrivalSessionAction,
        totalFileCount: Int,
        affectedFileCount: Int
    ) throws {
        let interaction = ArrivalSessionInteraction(
            sessionID: sessionID,
            occurredAtMilliseconds: Self.currentMilliseconds(),
            locationIdentifier: locationIdentifier,
            action: action,
            totalFileCount: totalFileCount,
            affectedFileCount: affectedFileCount
        )
        try eventStore.record(interaction)
    }

    public func fetchAllArrivalSessionInteractions() throws -> [ArrivalSessionInteraction] {
        try eventStore.fetchAllArrivalSessionInteractions()
    }

    /// Persist only routes that the app-side drag coordinator has resolved as
    /// successful and canonical. Actor isolation keeps the SQLite transaction off the
    /// main actor even when the observation originated in AppKit callbacks.
    public func recordSuccessfulRoutes(_ routes: [ItemRouteEvent]) throws {
        try eventStore.record(routes: routes)
    }

    public func fetchAllRoutes() throws -> [ItemRouteEvent] {
        try eventStore.fetchAllRoutes()
    }

    public func fetchLearnedRoutePatterns(
        detector: RoutePatternDetector = RoutePatternDetector()
    ) throws -> [LearnedRoutePattern] {
        try eventStore.fetchLearnedRoutePatterns(detector: detector)
    }

    public func fetchRouteSuggestions(
        for shelfItemIDs: [UUID],
        detector: RoutePatternDetector = RoutePatternDetector(),
        matcher: RouteSuggestionMatcher = RouteSuggestionMatcher()
    ) throws -> [UUID: SuggestedRoute] {
        try eventStore.fetchRouteSuggestions(
            for: shelfItemIDs,
            detector: detector,
            matcher: matcher
        )
    }

    private static func currentMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }

    private static func availableFilenameSuggestions(
        in drops: [RecordedDrop]
    ) -> [AvailableFilenameSuggestion] {
        drops.flatMap { drop in
            drop.files.compactMap { file in
                guard file.filenameSuggestionState == .available,
                      let displayName = file.smartLabel,
                      let suggestedFilename = file.filenameSuggestion
                else {
                    return nil
                }
                return AvailableFilenameSuggestion(
                    fileID: file.fileID,
                    shelfItemID: drop.event.shelfItemID,
                    originalFilename: file.displayName,
                    displayName: displayName,
                    suggestedFilename: suggestedFilename
                )
            }
        }
    }
}
