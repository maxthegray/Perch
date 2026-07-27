import Foundation
import GRDB
import XCTest
@testable import SmartPerchCore

final class ItemRouteEventStoreTests: XCTestCase {
    func testFolderAndApplicationRoutesPersistWithModeAndDwellTime() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let firstItem = UUID()
        let secondItem = UUID()
        try recordOriginalDrop(for: firstItem, in: store, category: .document)
        try recordOriginalDrop(for: secondItem, in: store, category: .image)

        let sessionID = UUID()
        let folderRoute = ItemRouteEvent(
            routeSessionID: sessionID,
            shelfItemID: firstItem,
            successfulDropAtMilliseconds: 1_700_000_010_000,
            dwellTimeMilliseconds: 10_000,
            destination: .folder(path: "/Users/test/Documents"),
            captureMethod: .filePromiseWrite,
            transferMode: .move
        )
        let appRoute = ItemRouteEvent(
            routeSessionID: sessionID,
            shelfItemID: secondItem,
            successfulDropAtMilliseconds: 1_700_000_010_000,
            dwellTimeMilliseconds: 9_000,
            destination: .application(
                bundleIdentifier: "com.apple.mail",
                name: "Mail"
            ),
            captureMethod: .applicationWindow,
            transferMode: .copy
        )

        try store.record(routes: [folderRoute, appRoute])
        let routes = try store.fetchAllRoutes()

        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes.map(\.routeSessionID), [sessionID, sessionID])
        let storedFolder = try XCTUnwrap(routes.first {
            $0.shelfItemID == firstItem
        })
        XCTAssertEqual(storedFolder.destination, folderRoute.destination)
        XCTAssertEqual(storedFolder.dwellTimeMilliseconds, 10_000)
        XCTAssertEqual(storedFolder.transferMode, .move)
        XCTAssertEqual(storedFolder.sourceAppBundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(storedFolder.sourceAppName, "Safari")
        XCTAssertEqual(storedFolder.category, .document)

        let storedApp = try XCTUnwrap(routes.first {
            $0.shelfItemID == secondItem
        })
        XCTAssertEqual(storedApp.destination, appRoute.destination)
        XCTAssertTrue(storedApp.wasCopy)
        XCTAssertEqual(storedApp.category, .image)
    }

    func testRouteBatchValidationIsTransactional() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let sessionID = UUID()
        let itemID = UUID()
        let valid = route(sessionID: sessionID, itemID: itemID)
        let duplicate = route(sessionID: sessionID, itemID: itemID)

        XCTAssertThrowsError(try store.record(routes: [valid, duplicate])) { error in
            XCTAssertEqual(
                error as? SmartPerchEventStoreError,
                .duplicateItemInRouteSession
            )
        }
        XCTAssertEqual(try store.fetchAllRoutes(), [])
    }

    func testAddingRoutesPreservesExistingDropOCRAndNameDataAcrossReopen() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let itemID = UUID()
        let originalDrop: RecordedDrop

        do {
            let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            originalDrop = try recordOriginalDrop(
                for: itemID,
                in: store,
                category: .image,
                ocrText: "Quarterly roadmap",
                smartLabel: "Quarterly Roadmap"
            )
            try store.record(routes: [route(itemID: itemID)])
        }

        let reopened = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        XCTAssertEqual(try reopened.fetchAllDrops(), [originalDrop])
        XCTAssertEqual(try reopened.fetchAllRoutes().count, 1)
    }

    func testRouteMigrationPreservesDatabaseFromPreviousSchema() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let itemID = UUID()
        let originalDrop: RecordedDrop

        do {
            let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            originalDrop = try recordOriginalDrop(
                for: itemID,
                in: store,
                category: .image,
                ocrText: "Migration keeps this text",
                smartLabel: "Migration Keeps This Text"
            )
        }

        // Recreate the exact state immediately before the route migration shipped:
        // all prior migrations are marked complete and the new table is absent.
        let rawDatabase = try DatabaseQueue(path: fixture.databaseURL.path)
        try rawDatabase.write { database in
            try database.drop(table: ItemRouteEvent.databaseTableName)
            try database.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier = 'createItemRouteEvents'
                    """
            )
        }

        let migrated = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        XCTAssertEqual(try migrated.fetchAllDrops(), [originalDrop])
        XCTAssertEqual(try migrated.fetchAllRoutes(), [])
        try migrated.record(routes: [route(itemID: itemID)])
        XCTAssertEqual(try migrated.fetchAllRoutes().count, 1)
    }

    func testRecorderExposesLearnedPatterns() async throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let recorder = SmartPerchDropRecorder(
            eventStore: try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        )
        let routes = (0..<3).map { _ in route() }

        try await recorder.recordSuccessfulRoutes(routes)
        let patterns = try await recorder.fetchLearnedRoutePatterns()

        XCTAssertEqual(patterns.count, 1)
        XCTAssertEqual(patterns[0].occurrenceCount, 3)
    }

    @discardableResult
    private func recordOriginalDrop(
        for itemID: UUID,
        in store: SmartPerchEventStore,
        category: FileCategory,
        ocrText: String? = nil,
        smartLabel: String? = nil
    ) throws -> RecordedDrop {
        let event = DropEvent(
            id: UUID(),
            batchID: UUID(),
            shelfItemID: itemID,
            occurredAtMilliseconds: 1_700_000_000_000,
            sourceAppBundleIdentifier: "com.apple.Safari",
            sourceAppName: "Safari",
            payloadKind: .file
        )
        let file = DroppedFileEvent(
            fileID: UUID(),
            dropEventID: event.id,
            ordinal: 0,
            displayName: "item.png",
            pathExtension: "png",
            contentTypeIdentifier: "public.png",
            byteCount: 42,
            isDirectory: false,
            isScreenCapture: true,
            category: category,
            classifierIdentifier: ExtensionHeuristicsClassifier.identifier,
            classifierVersion: ExtensionHeuristicsClassifier.version,
            ocrState: ocrText == nil ? .notEligible : .completed,
            ocrText: ocrText,
            ocrCompletedAtMilliseconds: ocrText == nil
                ? nil
                : 1_700_000_001_000,
            ocrDurationMilliseconds: ocrText == nil ? nil : 100,
            smartLabel: smartLabel,
            filenameSuggestion: smartLabel == nil ? nil : "quarterly-roadmap.png",
            filenameSuggestionState: smartLabel == nil ? .notEvaluated : .available,
            filenameSuggesterIdentifier: smartLabel == nil
                ? nil
                : ScreenshotFilenameSuggester.identifier,
            filenameSuggesterVersion: smartLabel == nil
                ? nil
                : ScreenshotFilenameSuggester.version
        )
        try store.record(event, files: [file])
        return RecordedDrop(event: event, files: [file])
    }

    private func route(
        sessionID: UUID = UUID(),
        itemID: UUID = UUID()
    ) -> ItemRouteEvent {
        ItemRouteEvent(
            routeSessionID: sessionID,
            shelfItemID: itemID,
            successfulDropAtMilliseconds: 1_700_000_010_000,
            dwellTimeMilliseconds: 10_000,
            destination: .folder(path: "/Users/test/Documents"),
            captureMethod: .filePromiseWrite,
            transferMode: .move,
            sourceAppBundleIdentifier: "com.apple.Safari",
            sourceAppName: "Safari",
            category: .document
        )
    }
}

private struct RouteDatabaseFixture {
    let directoryURL: URL
    let databaseURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchRoutes-\(UUID().uuidString)")
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
