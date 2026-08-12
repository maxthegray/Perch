import Foundation
import XCTest
@testable import SmartPerchCore

final class SmartPerchEventStoreTests: XCTestCase {
    func testEventAndFilesSurviveReopeningDatabase() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let event = makeEvent()
        let file = makeFile(dropEventID: event.id)

        do {
            let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            try store.record(event, files: [file])
        }

        let reopenedStore = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let drops = try reopenedStore.fetchAllDrops()

        XCTAssertEqual(drops, [RecordedDrop(event: event, files: [file])])
    }

    func testEventAndFilesAreValidatedBeforeTransaction() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let mismatchedFile = makeFile(dropEventID: UUID())

        XCTAssertThrowsError(try store.record(event, files: [mismatchedFile])) { error in
            XCTAssertEqual(
                error as? SmartPerchEventStoreError,
                .fileReferencesDifferentEvent
            )
        }
        XCTAssertEqual(try store.fetchAllDrops(), [])
    }

    func testFailedFileInsertRollsBackWholeEvent() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(dropEventID: event.id)

        XCTAssertThrowsError(try store.record(event, files: [file, file]))
        XCTAssertEqual(try store.fetchAllDrops(), [])
    }

    func testRetryWithSameEventIDCannotDuplicateHistory() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(dropEventID: event.id)

        try store.record(event, files: [file])
        XCTAssertThrowsError(try store.record(event, files: [file]))
        XCTAssertEqual(try store.fetchAllDrops().count, 1)
    }

    func testRecorderCapturesAndClassifiesFinalizedFile() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let fileURL = fixture.directoryURL.appendingPathComponent("notes.pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: fileURL)

        let eventStore = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let recorder = SmartPerchDropRecorder(eventStore: eventStore)
        let context = DropRecordingContext(
            eventID: UUID(),
            batchID: UUID(),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            sourceApplication: SourceApplicationContext(
                bundleIdentifier: "com.apple.finder",
                displayName: "Finder"
            )
        )
        let shelfItemID = UUID()

        try await recorder.recordFinalizedDrop(
            context: context,
            shelfItemID: shelfItemID,
            payloadKind: .file,
            fileURLs: [fileURL]
        )

        let drops = try await recorder.fetchAllDrops()
        let drop = try XCTUnwrap(drops.first)
        let file = try XCTUnwrap(drop.files.first)

        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drop.event.id, context.eventID)
        XCTAssertEqual(drop.event.batchID, context.batchID)
        XCTAssertEqual(drop.event.shelfItemID, shelfItemID)
        XCTAssertEqual(drop.event.occurredAtMilliseconds, 1_700_000_000_125)
        XCTAssertEqual(drop.event.sourceAppBundleIdentifier, "com.apple.finder")
        XCTAssertEqual(drop.event.sourceAppName, "Finder")
        XCTAssertEqual(drop.event.payloadKind, .file)
        XCTAssertEqual(file.displayName, "notes.pdf")
        XCTAssertEqual(file.pathExtension, "pdf")
        XCTAssertEqual(file.byteCount, 4)
        XCTAssertEqual(file.isDirectory, false)
        XCTAssertEqual(file.isScreenCapture, false)
        XCTAssertEqual(file.category, .document)
        XCTAssertEqual(file.classifierIdentifier, ExtensionHeuristicsClassifier.identifier)
        XCTAssertEqual(file.classifierVersion, ExtensionHeuristicsClassifier.version)
        XCTAssertEqual(file.ocrState, .pending)
        XCTAssertNil(file.ocrText)
        XCTAssertNil(file.ocrCompletedAtMilliseconds)
        XCTAssertNil(file.ocrDurationMilliseconds)
    }

    func testClippingIsRecordedWithoutInventingAFile() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let eventStore = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let recorder = SmartPerchDropRecorder(eventStore: eventStore)
        let context = DropRecordingContext(
            batchID: UUID(),
            occurredAt: Date(),
            sourceApplication: nil
        )

        try await recorder.recordFinalizedDrop(
            context: context,
            shelfItemID: UUID(),
            payloadKind: .clipping,
            fileURLs: []
        )

        let drops = try await recorder.fetchAllDrops()
        XCTAssertEqual(drops.count, 1)
        XCTAssertEqual(drops[0].event.payloadKind, .clipping)
        XCTAssertEqual(drops[0].files, [])
    }

    func testRecentArrivalIsRecordedAsAClassifiedFile() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let fileURL = fixture.directoryURL.appendingPathComponent("Screenshot.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

        let eventStore = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let recorder = SmartPerchDropRecorder(eventStore: eventStore)
        let context = DropRecordingContext(
            batchID: UUID(),
            occurredAt: Date(),
            sourceApplication: nil
        )
        let screenshotContext = makeScreenshotCaptureContext()

        try await recorder.recordFinalizedDrop(
            context: context,
            shelfItemID: UUID(),
            payloadKind: .recentArrival,
            fileURLs: [fileURL],
            screenshotCaptureContexts: [screenshotContext]
        )

        let drops = try await recorder.fetchAllDrops()
        let drop = try XCTUnwrap(drops.first)
        XCTAssertEqual(drop.event.payloadKind, .recentArrival)
        XCTAssertEqual(drop.files.first?.displayName, "Screenshot.png")
        XCTAssertEqual(drop.files.first?.category, .image)
        XCTAssertEqual(drop.files.first?.ocrState, .pending)
        XCTAssertEqual(
            drop.files.first?.screenshotCaptureContext,
            screenshotContext
        )
    }

    func testDerivedSmartNameIsPersistedForTheNewShelfItem() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let fileURL = fixture.directoryURL.appendingPathComponent("converted.heic")
        try Data([0x00, 0x01, 0x02]).write(to: fileURL)
        let recorder = SmartPerchDropRecorder(
            eventStore: try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        )
        let itemID = UUID()
        let fileID = UUID()

        let suggestion = try await recorder.recordDerivedFilenameSuggestion(
            context: DropRecordingContext(
                batchID: UUID(),
                occurredAt: Date(),
                sourceApplication: nil
            ),
            shelfItemID: itemID,
            fileURL: fileURL,
            fileID: fileID,
            displayName: "Quarterly Forecast",
            suggestedFilename: "quarterly-forecast.heic"
        )

        XCTAssertEqual(
            suggestion,
            AvailableFilenameSuggestion(
                fileID: fileID,
                shelfItemID: itemID,
                originalFilename: "converted.heic",
                displayName: "Quarterly Forecast",
                suggestedFilename: "quarterly-forecast.heic"
            )
        )
        let drops = try await recorder.fetchAllDrops()
        let drop = try XCTUnwrap(drops.first)
        XCTAssertEqual(drop.event.payloadKind, .transform)
        XCTAssertEqual(drop.files.first?.fileID, fileID)
        XCTAssertEqual(drop.files.first?.ocrState, .noText)
        XCTAssertEqual(drop.files.first?.filenameSuggestionState, .available)
        let preparedSuggestions = try await recorder.prepareFilenameSuggestions()
        XCTAssertEqual(preparedSuggestions, [suggestion])
    }

    func testOCRCompletionIsPersisted() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(dropEventID: event.id, ocrState: .pending)
        try store.record(event, files: [file])

        try store.finishOCR(
            fileID: file.fileID,
            state: .completed,
            text: "Invoice 4821",
            completedAtMilliseconds: 1_700_000_001_000,
            durationMilliseconds: 321
        )

        let updatedFile = try XCTUnwrap(store.fetchAllDrops().first?.files.first)
        XCTAssertEqual(updatedFile.ocrState, .completed)
        XCTAssertEqual(updatedFile.ocrText, "Invoice 4821")
        XCTAssertEqual(updatedFile.ocrCompletedAtMilliseconds, 1_700_000_001_000)
        XCTAssertEqual(updatedFile.ocrDurationMilliseconds, 321)
        XCTAssertEqual(updatedFile.filenameSuggestionState, .unavailable)
    }

    func testOCRCompletionPersistsACallerSpecificAnalyzerVersion() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(dropEventID: event.id, ocrState: .pending)
        try store.record(event, files: [file])
        let recorder = SmartPerchDropRecorder(eventStore: store)

        _ = try await recorder.completeOCR(
            fileID: file.fileID,
            text: "Quarterly Revenue Forecast",
            originalFilename: file.displayName,
            durationMilliseconds: 10,
            filenameSuggesterIdentifier: "pdf-visual-title",
            filenameSuggesterVersion: 3
        )

        let updatedFile = try XCTUnwrap(store.fetchAllDrops().first?.files.first)
        XCTAssertEqual(updatedFile.filenameSuggesterIdentifier, "pdf-visual-title")
        XCTAssertEqual(updatedFile.filenameSuggesterVersion, 3)
    }

    func testWindowContextNamesScreenshotWhenOCRFindsNoText() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(
            dropEventID: event.id,
            displayName: "Screenshot.png",
            ocrState: .pending
        )
        try store.record(event, files: [file])
        let recorder = SmartPerchDropRecorder(eventStore: store)

        let suggestion = try await recorder.completeOCR(
            fileID: file.fileID,
            text: nil,
            originalFilename: file.displayName,
            durationMilliseconds: 75,
            screenshotCaptureContext: makeScreenshotCaptureContext()
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Activity Monitor",
                suggestedFilename: "activity-monitor.png"
            )
        )
        let drops = try await recorder.fetchAllDrops()
        let updatedFile = try XCTUnwrap(drops.first?.files.first)
        XCTAssertEqual(updatedFile.ocrState, .noText)
        XCTAssertEqual(updatedFile.filenameSuggestionState, .available)
        XCTAssertEqual(updatedFile.smartLabel, "Activity Monitor")
    }

    func testRecorderPersistsAndAcceptsFilenameSuggestion() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(
            dropEventID: event.id,
            displayName: "Screenshot 2026-07-26 at 1.39.00 AM.png",
            ocrState: .pending
        )
        try store.record(event, files: [file])
        let recorder = SmartPerchDropRecorder(eventStore: store)
        let recognizedLines = [
            RecognizedTextLine(
                text: "Smart Perch invoice 4821",
                confidence: 0.94,
                minX: 0.2,
                minY: 0.5,
                width: 0.5,
                height: 0.07
            )
        ]

        let suggestion = try await recorder.completeOCR(
            fileID: file.fileID,
            text: "Smart Perch invoice 4821",
            recognizedLines: recognizedLines,
            originalFilename: file.displayName,
            durationMilliseconds: 120
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Smart Perch Invoice 4821",
                suggestedFilename: "smart-perch-invoice-4821.png"
            )
        )
        var drops = try await recorder.fetchAllDrops()
        var updatedFile = try XCTUnwrap(drops.first?.files.first)
        XCTAssertEqual(
            updatedFile.filenameSuggestion,
            suggestion?.suggestedFilename
        )
        XCTAssertEqual(updatedFile.smartLabel, suggestion?.displayName)
        let layoutData = try XCTUnwrap(updatedFile.ocrLayoutJSON?.data(using: .utf8))
        XCTAssertEqual(
            try JSONDecoder().decode([RecognizedTextLine].self, from: layoutData),
            recognizedLines
        )
        XCTAssertEqual(updatedFile.filenameSuggestionState, .available)
        XCTAssertEqual(
            updatedFile.filenameSuggesterIdentifier,
            ScreenshotFilenameSuggester.identifier
        )
        XCTAssertEqual(
            updatedFile.filenameSuggesterVersion,
            ScreenshotFilenameSuggester.version
        )

        try await recorder.acceptFilenameSuggestion(
            fileID: file.fileID,
            acceptedFilename: "smart-perch-invoice-4821-2.png"
        )

        drops = try await recorder.fetchAllDrops()
        updatedFile = try XCTUnwrap(drops.first?.files.first)
        XCTAssertEqual(updatedFile.filenameSuggestionState, .accepted)
        XCTAssertEqual(updatedFile.acceptedFilename, "smart-perch-invoice-4821-2.png")
        XCTAssertNotNil(updatedFile.filenameSuggestionDecidedAtMilliseconds)
    }

    func testExistingOCRTextIsBackfilledWithoutRunningOCRAgain() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let file = makeFile(
            dropEventID: event.id,
            displayName: "Screenshot.png",
            ocrState: .completed,
            ocrText: "Quarterly revenue forecast"
        )
        try store.record(event, files: [file])
        let recorder = SmartPerchDropRecorder(eventStore: store)

        let suggestions = try await recorder.prepareFilenameSuggestions()

        XCTAssertEqual(
            suggestions,
            [
                AvailableFilenameSuggestion(
                    fileID: file.fileID,
                    shelfItemID: event.shelfItemID,
                    originalFilename: "Screenshot.png",
                    displayName: "Quarterly Revenue Forecast",
                    suggestedFilename: "quarterly-revenue-forecast.png"
                )
            ]
        )

        // Preparing again is idempotent and returns the same unresolved suggestion.
        let preparedAgain = try await recorder.prepareFilenameSuggestions()
        XCTAssertEqual(preparedAgain, suggestions)
    }

    func testOutdatedSmartNameIsReevaluatedUsingStoredLayout() async throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let event = makeEvent()
        let recognizedLines = [
            RecognizedTextLine(
                text: "Lachlan Wession",
                confidence: 0.92,
                minX: 0.45,
                minY: 0.80,
                width: 0.12,
                height: 0.014
            ),
            RecognizedTextLine(
                text: "But then im leaving for houston so idk",
                confidence: 0.94,
                minX: 0.37,
                minY: 0.39,
                width: 0.30,
                height: 0.016
            ),
            RecognizedTextLine(
                text: "iMessage",
                confidence: 0.95,
                minX: 0.37,
                minY: 0.32,
                width: 0.08,
                height: 0.014
            )
        ]
        let layoutJSON = try String(
            data: JSONEncoder().encode(recognizedLines),
            encoding: .utf8
        ).unwrap()
        let file = DroppedFileEvent(
            fileID: UUID(),
            dropEventID: event.id,
            ordinal: 0,
            displayName: "Screenshot.png",
            pathExtension: "png",
            contentTypeIdentifier: "public.png",
            byteCount: 1_024,
            isDirectory: false,
            isScreenCapture: true,
            category: .image,
            classifierIdentifier: ExtensionHeuristicsClassifier.identifier,
            classifierVersion: ExtensionHeuristicsClassifier.version,
            ocrState: .completed,
            ocrText: recognizedLines.map(\.text).joined(separator: "\n"),
            ocrCompletedAtMilliseconds: 1_700_000_001_000,
            ocrDurationMilliseconds: 100,
            ocrLayoutJSON: layoutJSON,
            smartLabel: "Then Im Leaving Houston",
            filenameSuggestion: "then-im-leaving-houston.png",
            filenameSuggestionState: .available,
            filenameSuggesterIdentifier: ScreenshotFilenameSuggester.identifier,
            filenameSuggesterVersion: 2
        )
        try store.record(event, files: [file])
        let recorder = SmartPerchDropRecorder(eventStore: store)

        let suggestions = try await recorder.prepareFilenameSuggestions()

        XCTAssertEqual(
            suggestions,
            [
                AvailableFilenameSuggestion(
                    fileID: file.fileID,
                    shelfItemID: event.shelfItemID,
                    originalFilename: "Screenshot.png",
                    displayName: "Messages — Lachlan Wession",
                    suggestedFilename: "messages-lachlan-wession.png"
                )
            ]
        )
    }

    func testArrivalSessionInteractionIsPersisted() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let interaction = ArrivalSessionInteraction(
            id: UUID(),
            sessionID: UUID(),
            occurredAtMilliseconds: 1_700_000_001_000,
            locationIdentifier: "downloads",
            action: .adoptedAll,
            totalFileCount: 3,
            affectedFileCount: 3
        )

        try store.record(interaction)

        XCTAssertEqual(
            try store.fetchAllArrivalSessionInteractions(),
            [interaction]
        )
    }

    func testInvalidArrivalSessionInteractionIsRejected() throws {
        let fixture = try TemporaryDatabaseFixture()
        defer { fixture.remove() }

        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let interaction = ArrivalSessionInteraction(
            sessionID: UUID(),
            occurredAtMilliseconds: 1_700_000_001_000,
            locationIdentifier: "downloads",
            action: .adoptedAll,
            totalFileCount: 3,
            affectedFileCount: 4
        )

        XCTAssertThrowsError(try store.record(interaction)) { error in
            XCTAssertEqual(
                error as? SmartPerchEventStoreError,
                .invalidArrivalSessionInteraction
            )
        }
        XCTAssertEqual(try store.fetchAllArrivalSessionInteractions(), [])
    }

    private func makeEvent() -> DropEvent {
        DropEvent(
            id: UUID(),
            batchID: UUID(),
            shelfItemID: UUID(),
            occurredAtMilliseconds: 1_700_000_000_000,
            sourceAppBundleIdentifier: "com.apple.finder",
            sourceAppName: "Finder",
            payloadKind: .file
        )
    }

    private func makeScreenshotCaptureContext() -> ScreenshotCaptureContext {
        ScreenshotCaptureContext(
            capturedAtMilliseconds: 1_700_000_000_000,
            captureRect: ScreenshotScreenRect(
                x: 20,
                y: 30,
                width: 1_200,
                height: 800
            ),
            ownerProcessIdentifier: 42,
            ownerBundleIdentifier: "com.apple.ActivityMonitor",
            ownerName: "Activity Monitor",
            windowTitle: "Activity Monitor",
            matchedWindowRect: ScreenshotScreenRect(
                x: 0,
                y: 0,
                width: 1_280,
                height: 900
            ),
            visibleCoverage: 0.94
        )
    }

    private func makeFile(
        dropEventID: UUID,
        displayName: String = "report.pdf",
        ocrState: OCRProcessingState = .notEvaluated,
        ocrText: String? = nil
    ) -> DroppedFileEvent {
        DroppedFileEvent(
            fileID: UUID(),
            dropEventID: dropEventID,
            ordinal: 0,
            displayName: displayName,
            pathExtension: (displayName as NSString).pathExtension.lowercased(),
            contentTypeIdentifier: "com.adobe.pdf",
            byteCount: 42,
            isDirectory: false,
            isScreenCapture: false,
            category: .document,
            classifierIdentifier: ExtensionHeuristicsClassifier.identifier,
            classifierVersion: ExtensionHeuristicsClassifier.version,
            ocrState: ocrState,
            ocrText: ocrText,
            ocrCompletedAtMilliseconds: ocrText == nil ? nil : 1_700_000_001_000,
            ocrDurationMilliseconds: nil
        )
    }
}

private extension Optional {
    func unwrap(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}

private struct TemporaryDatabaseFixture {
    let directoryURL: URL
    let databaseURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchTests-\(UUID().uuidString)", isDirectory: true)
        databaseURL = directoryURL.appendingPathComponent("events.sqlite")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
