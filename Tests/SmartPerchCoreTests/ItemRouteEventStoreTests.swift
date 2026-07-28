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

        // Recreate the exact state immediately before the route migrations shipped: all
        // prior migrations are marked complete and the new table is absent. Every route
        // migration must be unmarked, not just the first — leaving a later one recorded
        // would let the table be rebuilt without the columns that migration adds, which
        // is a state no real database is ever in.
        let rawDatabase = try DatabaseQueue(path: fixture.databaseURL.path)
        try rawDatabase.write { database in
            try database.drop(table: ItemRouteEvent.databaseTableName)
            try database.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier IN ('createItemRouteEvents', 'addItemRouteEventOrigin')
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

    /// The upgrade a real user actually performs: routes recorded by the previous
    /// release, opened by a build that adds the origin column. Their history is all
    /// genuine drags, so it must keep counting as evidence.
    func testRoutesRecordedBeforeTheOriginColumnReadBackAsManualDrags() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let itemID = UUID()

        do {
            let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            try recordOriginalDrop(for: itemID, in: store, category: .document)
            try store.record(routes: [route(itemID: itemID)])
        }

        // Roll the schema back to the state that release left behind.
        let rawDatabase = try DatabaseQueue(path: fixture.databaseURL.path)
        try rawDatabase.write { database in
            try database.alter(table: ItemRouteEvent.databaseTableName) { table in
                table.drop(column: "origin")
            }
            try database.execute(
                sql: """
                    DELETE FROM grdb_migrations
                    WHERE identifier = 'addItemRouteEventOrigin'
                    """
            )
        }

        let migrated = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        let routes = try migrated.fetchAllRoutes()

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].origin, .manualDrag)
    }

    func testOriginSurvivesAReopen() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let filedItem = UUID()

        do {
            let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            try recordOriginalDrop(for: filedItem, in: store, category: .document)
            try store.record(routes: [
                route(itemID: filedItem, origin: .acceptedSuggestion)
            ])
        }

        let routes = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
            .fetchAllRoutes()

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].origin, .acceptedSuggestion)
        XCTAssertEqual(routes[0].captureMethod, .perchFiling)
    }

    func testShelfItemsAreOfferedTheRouteLearnedForTheirOwnDropContext() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)

        // Three separate Safari documents, all dragged to the same folder.
        for _ in 0..<3 {
            let routedItem = UUID()
            try recordOriginalDrop(for: routedItem, in: store, category: .document)
            try store.record(routes: [route(itemID: routedItem)])
        }

        // A fourth Safari document is still sitting on the shelf, alongside an image
        // whose category has never established a route.
        let waitingDocument = UUID()
        let waitingImage = UUID()
        try recordOriginalDrop(for: waitingDocument, in: store, category: .document)
        try recordOriginalDrop(for: waitingImage, in: store, category: .image)

        let suggestions = try store.fetchRouteSuggestions(
            for: [waitingDocument, waitingImage]
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(
            suggestions[waitingDocument]?.destination,
            .folder(path: "/Users/test/Documents")
        )
        XCTAssertNil(suggestions[waitingImage])
    }

    func testAnItemWithNoDropRecordIsSimplyAbsentFromTheSuggestions() throws {
        let fixture = try RouteDatabaseFixture()
        defer { fixture.remove() }
        let store = try SmartPerchEventStore(databaseURL: fixture.databaseURL)
        for _ in 0..<3 {
            let routedItem = UUID()
            try recordOriginalDrop(for: routedItem, in: store, category: .document)
            try store.record(routes: [route(itemID: routedItem)])
        }

        XCTAssertTrue(try store.fetchRouteSuggestions(for: [UUID()]).isEmpty)
        XCTAssertTrue(try store.fetchRouteSuggestions(for: []).isEmpty)
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
        itemID: UUID = UUID(),
        origin: RouteEventOrigin = .manualDrag
    ) -> ItemRouteEvent {
        ItemRouteEvent(
            routeSessionID: sessionID,
            shelfItemID: itemID,
            successfulDropAtMilliseconds: 1_700_000_010_000,
            dwellTimeMilliseconds: 10_000,
            destination: .folder(path: "/Users/test/Documents"),
            captureMethod: origin == .acceptedSuggestion ? .perchFiling : .filePromiseWrite,
            transferMode: .move,
            sourceAppBundleIdentifier: "com.apple.Safari",
            sourceAppName: "Safari",
            category: .document,
            origin: origin
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
