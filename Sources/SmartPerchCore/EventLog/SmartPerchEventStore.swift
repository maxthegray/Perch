import Foundation
import GRDB

public enum SmartPerchEventStoreError: Error, Equatable {
    case fileReferencesDifferentEvent
    case invalidArrivalSessionInteraction
    case invalidItemRouteEvent
    case duplicateItemInRouteSession
    case invalidOCRCompletion
    case invalidFilenameSuggestion
    case filenameSuggestionNotAvailable(UUID)
    case fileNotFound(UUID)
}

/// SQLite persistence for Smart Perch's local event history.
///
/// A `DatabaseQueue` is sufficient because Perch is a single-process app with tiny,
/// infrequent writes. The recorder actor keeps metadata capture and database access
/// off the main actor.
public final class SmartPerchEventStore: @unchecked Sendable {
    private let database: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }

        database = try DatabaseQueue(
            path: databaseURL.path,
            configuration: configuration
        )
        try Self.migrator.migrate(database)
    }

    /// Insert the event and all of its files in one transaction. Reusing an event ID
    /// is rejected by the primary key, preventing retries from creating duplicates.
    public func record(_ event: DropEvent, files: [DroppedFileEvent]) throws {
        guard files.allSatisfy({ $0.dropEventID == event.id }) else {
            throw SmartPerchEventStoreError.fileReferencesDifferentEvent
        }

        try database.write { database in
            try event.insert(database)
            for file in files {
                try file.insert(database)
            }
        }
    }

    public func fetchAllDrops() throws -> [RecordedDrop] {
        try database.read { database in
            let events = try DropEvent
                .order(Column("occurred_at_ms"), Column("id"))
                .fetchAll(database)
            let files = try DroppedFileEvent
                .order(Column("drop_event_id"), Column("ordinal"))
                .fetchAll(database)
            let filesByEvent = Dictionary(grouping: files, by: \.dropEventID)

            return events.map {
                RecordedDrop(event: $0, files: filesByEvent[$0.id] ?? [])
            }
        }
    }

    public func record(_ interaction: ArrivalSessionInteraction) throws {
        guard interaction.totalFileCount > 0,
              interaction.affectedFileCount >= 0,
              interaction.affectedFileCount <= interaction.totalFileCount
        else {
            throw SmartPerchEventStoreError.invalidArrivalSessionInteraction
        }
        try database.write { database in
            try interaction.insert(database)
        }
    }

    public func fetchAllArrivalSessionInteractions() throws -> [ArrivalSessionInteraction] {
        try database.read { database in
            try ArrivalSessionInteraction
                .order(Column("occurred_at_ms"), Column("id"))
                .fetchAll(database)
        }
    }

    /// Append a drag's successful item routes in one transaction. Source-app and
    /// category context are copied from the item's original drop record at insertion
    /// time, so later pattern queries remain pure and do not depend on shelf files
    /// that may already have been retired.
    public func record(routes: [ItemRouteEvent]) throws {
        guard !routes.isEmpty else { return }

        let itemSessionKeys = routes.map {
            "\($0.routeSessionID.uuidString):\($0.shelfItemID.uuidString)"
        }
        guard Set(itemSessionKeys).count == itemSessionKeys.count else {
            throw SmartPerchEventStoreError.duplicateItemInRouteSession
        }
        guard routes.allSatisfy(Self.isValidRoute) else {
            throw SmartPerchEventStoreError.invalidItemRouteEvent
        }

        try database.write { database in
            for route in routes {
                let context = try Self.learningContext(
                    for: route.shelfItemID,
                    in: database
                )
                try route.addingLearningContext(
                    sourceAppBundleIdentifier: context?.sourceAppBundleIdentifier,
                    sourceAppName: context?.sourceAppName,
                    category: context?.category
                ).insert(database)
            }
        }
    }

    public func fetchAllRoutes() throws -> [ItemRouteEvent] {
        try database.read { database in
            try ItemRouteEvent
                .order(
                    Column("successful_drop_at_ms"),
                    Column("route_session_id"),
                    Column("shelf_item_id")
                )
                .fetchAll(database)
        }
    }

    public func fetchLearnedRoutePatterns(
        detector: RoutePatternDetector = RoutePatternDetector()
    ) throws -> [LearnedRoutePattern] {
        detector.detectPatterns(in: try fetchAllRoutes())
    }

    /// The learning context of each requested shelf item that has a drop record.
    /// Items with no record (or none carrying usable context) are simply absent.
    public func fetchLearningContexts(
        for shelfItemIDs: [UUID]
    ) throws -> [UUID: RouteLearningContext] {
        guard !shelfItemIDs.isEmpty else { return [:] }
        return try database.read { database in
            var contexts: [UUID: RouteLearningContext] = [:]
            for shelfItemID in Set(shelfItemIDs) {
                guard let context = try Self.learningContext(
                    for: shelfItemID,
                    in: database
                ) else {
                    continue
                }
                contexts[shelfItemID] = context
            }
            return contexts
        }
    }

    /// One read for the whole shelf: resolve each item's context, detect patterns from
    /// the route history, and pair them up.
    public func fetchRouteSuggestions(
        for shelfItemIDs: [UUID],
        detector: RoutePatternDetector = RoutePatternDetector(),
        matcher: RouteSuggestionMatcher = RouteSuggestionMatcher()
    ) throws -> [UUID: SuggestedRoute] {
        guard !shelfItemIDs.isEmpty else { return [:] }
        let patterns = try fetchLearnedRoutePatterns(detector: detector)
        guard !patterns.isEmpty else { return [:] }
        return matcher.suggestions(
            forItemContexts: try fetchLearningContexts(for: shelfItemIDs),
            patterns: patterns
        )
    }

    public func finishOCR(
        fileID: UUID,
        state: OCRProcessingState,
        text: String?,
        completedAtMilliseconds: Int64,
        durationMilliseconds: Int64?,
        ocrLayoutJSON: String? = nil,
        smartLabel: String? = nil,
        filenameSuggestion: String? = nil,
        filenameSuggesterIdentifier: String? = nil,
        filenameSuggesterVersion: Int? = nil
    ) throws {
        let hasText = text?.isEmpty == false
        guard (state == .completed && hasText)
                || (state == .noText && !hasText)
                || (state == .failed && !hasText)
        else {
            throw SmartPerchEventStoreError.invalidOCRCompletion
        }

        let hasSuggestion = filenameSuggestion?.isEmpty == false
        guard !hasSuggestion
                || ((state == .completed || state == .noText)
                    && smartLabel?.isEmpty == false
                    && filenameSuggesterIdentifier?.isEmpty == false
                    && filenameSuggesterVersion != nil)
        else {
            throw SmartPerchEventStoreError.invalidFilenameSuggestion
        }
        let suggestionState: FilenameSuggestionState = hasSuggestion
            ? .available
            : .unavailable

        try database.write { database in
            try database.execute(
                sql: """
                    UPDATE dropped_files
                    SET ocr_state = ?,
                        ocr_text = ?,
                        ocr_completed_at_ms = ?,
                        ocr_duration_ms = ?,
                        ocr_layout_json = ?,
                        smart_label = ?,
                        filename_suggestion = ?,
                        filename_suggestion_state = ?,
                        filename_suggester_identifier = ?,
                        filename_suggester_version = ?
                    WHERE file_id = ?
                    """,
                arguments: [
                    state,
                    text,
                    completedAtMilliseconds,
                    durationMilliseconds,
                    ocrLayoutJSON,
                    smartLabel,
                    filenameSuggestion,
                    suggestionState,
                    filenameSuggesterIdentifier,
                    filenameSuggesterVersion,
                    fileID
                ]
            )
            guard database.changesCount == 1 else {
                throw SmartPerchEventStoreError.fileNotFound(fileID)
            }
        }
    }

    /// Evaluate an older OCR record after a schema migration without running Vision
    /// again. The conditional update makes startup backfilling idempotent.
    public func storeFilenameSuggestionEvaluation(
        fileID: UUID,
        smartLabel: String?,
        filenameSuggestion: String?,
        filenameSuggesterIdentifier: String,
        filenameSuggesterVersion: Int
    ) throws {
        guard !filenameSuggesterIdentifier.isEmpty else {
            throw SmartPerchEventStoreError.invalidFilenameSuggestion
        }
        let normalizedSuggestion = filenameSuggestion?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedLabel = smartLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedSuggestion?.isEmpty != true,
              normalizedLabel?.isEmpty != true,
              (normalizedSuggestion == nil) == (normalizedLabel == nil)
        else {
            throw SmartPerchEventStoreError.invalidFilenameSuggestion
        }
        let suggestionState: FilenameSuggestionState = normalizedSuggestion == nil
            ? .unavailable
            : .available

        try database.write { database in
            try database.execute(
                sql: """
                    UPDATE dropped_files
                    SET smart_label = ?,
                        filename_suggestion = ?,
                        filename_suggestion_state = ?,
                        filename_suggester_identifier = ?,
                        filename_suggester_version = ?
                    WHERE file_id = ?
                      AND ocr_state IN (?, ?)
                      AND (
                        filename_suggestion_state = ?
                        OR (
                            filename_suggestion_state = ?
                            AND (
                                smart_label IS NULL
                                OR filename_suggester_version != ?
                            )
                        )
                      )
                    """,
                arguments: [
                    normalizedLabel,
                    normalizedSuggestion,
                    suggestionState,
                    filenameSuggesterIdentifier,
                    filenameSuggesterVersion,
                    fileID,
                    OCRProcessingState.completed,
                    OCRProcessingState.noText,
                    FilenameSuggestionState.notEvaluated,
                    FilenameSuggestionState.available,
                    filenameSuggesterVersion
                ]
            )
        }
    }

    public func resolveFilenameSuggestion(
        fileID: UUID,
        state: FilenameSuggestionState,
        acceptedFilename: String?,
        decidedAtMilliseconds: Int64
    ) throws {
        let hasAcceptedFilename = acceptedFilename?.isEmpty == false
        guard (state == .accepted && hasAcceptedFilename)
                || (state == .dismissed && !hasAcceptedFilename)
        else {
            throw SmartPerchEventStoreError.invalidFilenameSuggestion
        }

        try database.write { database in
            try database.execute(
                sql: """
                    UPDATE dropped_files
                    SET filename_suggestion_state = ?,
                        filename_suggestion_decided_at_ms = ?,
                        accepted_filename = ?
                    WHERE file_id = ?
                      AND filename_suggestion_state = ?
                    """,
                arguments: [
                    state,
                    decidedAtMilliseconds,
                    acceptedFilename,
                    fileID,
                    FilenameSuggestionState.available
                ]
            )
            guard database.changesCount == 1 else {
                throw SmartPerchEventStoreError.filenameSuggestionNotAvailable(fileID)
            }
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createSmartPerchDropLog") { database in
            try database.create(table: DropEvent.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("batch_id", .text).notNull()
                table.column("shelf_item_id", .text).notNull()
                table.column("occurred_at_ms", .integer).notNull()
                table.column("source_app_bundle_identifier", .text)
                table.column("source_app_name", .text)
                table.column("payload_kind", .text).notNull()
                table.column("schema_version", .integer).notNull()
            }

            try database.create(table: DroppedFileEvent.databaseTableName) { table in
                table.column("file_id", .text).primaryKey()
                table.column("drop_event_id", .text)
                    .notNull()
                    .references(DropEvent.databaseTableName, onDelete: .cascade)
                table.column("ordinal", .integer).notNull()
                table.column("display_name", .text).notNull()
                table.column("path_extension", .text).notNull()
                table.column("content_type_identifier", .text)
                table.column("byte_count", .integer)
                table.column("is_directory", .boolean)
                table.column("category", .text).notNull()
                table.column("classifier_identifier", .text).notNull()
                table.column("classifier_version", .integer).notNull()
                table.column("ocr_state", .text).notNull()
                table.column("ocr_text", .text)
                table.uniqueKey(["drop_event_id", "ordinal"])
            }

            try database.create(
                index: "drop_events_by_batch",
                on: DropEvent.databaseTableName,
                columns: ["batch_id"]
            )
            try database.create(
                index: "drop_events_by_time",
                on: DropEvent.databaseTableName,
                columns: ["occurred_at_ms"]
            )
            try database.create(
                index: "drop_events_by_source_and_time",
                on: DropEvent.databaseTableName,
                columns: ["source_app_bundle_identifier", "occurred_at_ms"]
            )
            try database.create(
                index: "dropped_files_by_category",
                on: DroppedFileEvent.databaseTableName,
                columns: ["category", "drop_event_id"]
            )
        }

        migrator.registerMigration("addScreenshotOCRMetadata") { database in
            try database.alter(table: DroppedFileEvent.databaseTableName) { table in
                table.add(column: "is_screen_capture", .boolean)
                table.add(column: "ocr_completed_at_ms", .integer)
                table.add(column: "ocr_duration_ms", .integer)
            }
        }

        migrator.registerMigration("createArrivalSessionInteractions") { database in
            try database.create(table: ArrivalSessionInteraction.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull()
                table.column("occurred_at_ms", .integer).notNull()
                table.column("location_identifier", .text).notNull()
                table.column("action", .text).notNull()
                table.column("total_file_count", .integer).notNull()
                table.column("affected_file_count", .integer).notNull()
            }
            try database.create(
                index: "arrival_session_interactions_by_session_and_time",
                on: ArrivalSessionInteraction.databaseTableName,
                columns: ["session_id", "occurred_at_ms"]
            )
        }

        migrator.registerMigration("addScreenshotFilenameSuggestions") { database in
            try database.alter(table: DroppedFileEvent.databaseTableName) { table in
                table.add(column: "filename_suggestion", .text)
                table.add(column: "filename_suggestion_state", .text)
                    .notNull()
                    .defaults(to: FilenameSuggestionState.notEvaluated.rawValue)
                table.add(column: "filename_suggester_identifier", .text)
                table.add(column: "filename_suggester_version", .integer)
                table.add(column: "filename_suggestion_decided_at_ms", .integer)
                table.add(column: "accepted_filename", .text)
            }
            try database.create(
                index: "dropped_files_by_filename_suggestion_state",
                on: DroppedFileEvent.databaseTableName,
                columns: ["filename_suggestion_state", "drop_event_id"]
            )
        }

        migrator.registerMigration("addScreenshotSmartNamesAndOCRLayout") { database in
            try database.alter(table: DroppedFileEvent.databaseTableName) { table in
                table.add(column: "ocr_layout_json", .text)
                table.add(column: "smart_label", .text)
            }
        }

        migrator.registerMigration("addScreenshotCaptureContext") { database in
            try database.alter(table: DroppedFileEvent.databaseTableName) { table in
                table.add(column: "screenshot_capture_context_json", .text)
            }
        }

        migrator.registerMigration("createItemRouteEvents") { database in
            try database.create(table: ItemRouteEvent.databaseTableName) { table in
                table.column("id", .text).primaryKey()
                table.column("route_session_id", .text).notNull()
                table.column("shelf_item_id", .text).notNull()
                table.column("successful_drop_at_ms", .integer).notNull()
                table.column("dwell_time_ms", .integer).notNull()
                table.column("destination_kind", .text).notNull()
                table.column("destination_folder_path", .text)
                table.column("destination_app_bundle_identifier", .text)
                table.column("destination_app_name", .text)
                table.column("capture_method", .text).notNull()
                table.column("transfer_mode", .text).notNull()
                table.column("source_app_bundle_identifier", .text)
                table.column("source_app_name", .text)
                table.column("category", .text)
                table.column("schema_version", .integer).notNull()
                table.uniqueKey(["route_session_id", "shelf_item_id"])
            }
            try database.create(
                index: "item_route_events_by_session",
                on: ItemRouteEvent.databaseTableName,
                columns: ["route_session_id"]
            )
            try database.create(
                index: "item_route_events_by_item_and_time",
                on: ItemRouteEvent.databaseTableName,
                columns: ["shelf_item_id", "successful_drop_at_ms"]
            )
            try database.create(
                index: "item_route_events_by_context",
                on: ItemRouteEvent.databaseTableName,
                columns: [
                    "source_app_bundle_identifier",
                    "category",
                    "successful_drop_at_ms"
                ]
            )
        }

        migrator.registerMigration("addItemRouteEventOrigin") { database in
            try database.alter(table: ItemRouteEvent.databaseTableName) { table in
                table.add(column: "origin", .text)
                    .notNull()
                    .defaults(to: RouteEventOrigin.manualDrag.rawValue)
            }
        }

        return migrator
    }

    private static func isValidRoute(_ route: ItemRouteEvent) -> Bool {
        guard route.successfulDropAtMilliseconds >= 0,
              route.dwellTimeMilliseconds >= 0
        else {
            return false
        }

        switch (route.destination, route.captureMethod) {
        case let (.folder(path), .filePromiseWrite),
             let (.folder(path), .perchFiling):
            return !path.isEmpty && (path as NSString).isAbsolutePath
        case let (.application(bundleIdentifier, name), .applicationWindow):
            return bundleIdentifier?.isEmpty == false || !name.isEmpty
        case (.folder, .applicationWindow),
             (.application, .filePromiseWrite),
             (.application, .perchFiling):
            return false
        }
    }

    private static func learningContext(
        for shelfItemID: UUID,
        in database: Database
    ) throws -> RouteLearningContext? {
        let rows = try Row.fetchAll(
            database,
            sql: """
                SELECT d.source_app_bundle_identifier,
                       d.source_app_name,
                       f.category
                FROM drop_events d
                LEFT JOIN dropped_files f ON f.drop_event_id = d.id
                WHERE d.id = (
                    SELECT latest.id
                    FROM drop_events latest
                    WHERE latest.shelf_item_id = ?
                    ORDER BY latest.occurred_at_ms DESC, latest.id DESC
                    LIMIT 1
                )
                ORDER BY f.ordinal
                """,
            arguments: [shelfItemID]
        )
        guard let first = rows.first else { return nil }

        let categories = Set(rows.compactMap {
            FileCategory(rawValue: $0["category"] as String? ?? "")
        })
        let category: FileCategory?
        if categories.count == 1 {
            category = categories.first
        } else if categories.count > 1 {
            category = .other
        } else {
            category = nil
        }

        return RouteLearningContext(
            sourceAppBundleIdentifier: first["source_app_bundle_identifier"],
            sourceAppName: first["source_app_name"],
            category: category
        )
    }
}
