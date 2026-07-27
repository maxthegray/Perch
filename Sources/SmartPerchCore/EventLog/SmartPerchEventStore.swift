import Foundation
import GRDB

public enum SmartPerchEventStoreError: Error, Equatable {
    case fileReferencesDifferentEvent
    case invalidArrivalSessionInteraction
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
                || (state == .completed
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
                      AND ocr_state = ?
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

        return migrator
    }
}
