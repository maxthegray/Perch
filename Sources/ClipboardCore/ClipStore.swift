import Foundation
import GRDB

public struct ClipSummary: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let kind: ClipKind
    public let title: String
    public let searchText: String
    public let filePaths: [String]
    public let sourceBundleID: String?
    public let thumbnail: Data?
    public let firstCopiedAt: Date
    public let lastCopiedAt: Date

    public init(
        id: Int64, kind: ClipKind, title: String, searchText: String, filePaths: [String],
        sourceBundleID: String?, thumbnail: Data?, firstCopiedAt: Date, lastCopiedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.searchText = searchText
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.thumbnail = thumbnail
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
    }
}

/// SQLite history of copied clips, newest first, capped at `limit`.
public final class ClipStore: @unchecked Sendable {
    public static let defaultLimit = 200

    private let database: DatabaseQueue
    private let limit: Int

    public init(databaseURL: URL, limit: Int = ClipStore.defaultLimit) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        self.limit = limit
        try Self.migrator.migrate(database)
    }

    /// Adds the clip, or moves an existing clip with the same content to the top and
    /// refreshes it with this copy's representations. Returns the clip's id.
    @discardableResult
    public func record(_ capture: ClipCapture, sourceBundleID: String?, at date: Date) throws -> Int64 {
        try database.write { db in
            let existing = try Int64.fetchOne(
                db, sql: "SELECT id FROM clip WHERE contentHash = ?", arguments: [capture.contentHash]
            )
            let id: Int64
            if let existing {
                try db.execute(
                    sql: """
                        UPDATE clip SET kind = ?, title = ?, searchText = ?, filePaths = ?,
                            sourceBundleID = COALESCE(?, sourceBundleID),
                            thumbnail = COALESCE(?, thumbnail), lastCopiedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        capture.kind.rawValue, capture.title, capture.searchText,
                        capture.filePaths.joined(separator: "\n"), sourceBundleID,
                        capture.thumbnail, date, existing
                    ]
                )
                try db.execute(sql: "DELETE FROM clipRepresentation WHERE clipID = ?", arguments: [existing])
                id = existing
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO clip (contentHash, kind, title, searchText, filePaths,
                            sourceBundleID, thumbnail, firstCopiedAt, lastCopiedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        capture.contentHash, capture.kind.rawValue, capture.title,
                        capture.searchText, capture.filePaths.joined(separator: "\n"),
                        sourceBundleID, capture.thumbnail, date, date
                    ]
                )
                id = db.lastInsertedRowID
            }

            for (position, representation) in capture.representations.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO clipRepresentation (clipID, itemIndex, position, type, data)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [id, representation.itemIndex, position, representation.type, representation.data]
                )
            }

            try db.execute(
                sql: """
                    DELETE FROM clip WHERE id NOT IN (
                        SELECT id FROM clip ORDER BY lastCopiedAt DESC, id DESC LIMIT ?
                    )
                    """,
                arguments: [limit]
            )
            return id
        }
    }

    public func recent() throws -> [ClipSummary] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, kind, title, searchText, filePaths, sourceBundleID, thumbnail,
                        firstCopiedAt, lastCopiedAt
                    FROM clip ORDER BY lastCopiedAt DESC, id DESC
                    """
            ).map { row in
                let paths: String = row["filePaths"]
                return ClipSummary(
                    id: row["id"],
                    kind: ClipKind(rawValue: row["kind"]) ?? .text,
                    title: row["title"],
                    searchText: row["searchText"],
                    filePaths: paths.isEmpty ? [] : paths.components(separatedBy: "\n"),
                    sourceBundleID: row["sourceBundleID"],
                    thumbnail: row["thumbnail"],
                    firstCopiedAt: row["firstCopiedAt"],
                    lastCopiedAt: row["lastCopiedAt"]
                )
            }
        }
    }

    public func representations(for id: Int64) throws -> [ClipRepresentation] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT itemIndex, type, data FROM clipRepresentation
                    WHERE clipID = ? ORDER BY position
                    """,
                arguments: [id]
            ).map { row in
                ClipRepresentation(itemIndex: row["itemIndex"], type: row["type"], data: row["data"])
            }
        }
    }

    public func delete(id: Int64) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [id])
        }
    }

    public func deleteAll() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM clip")
        }
        try database.vacuum()
    }

    /// Deletes a closed store's database and its SQLite sidecar files.
    public static func removeFiles(at databaseURL: URL, fileManager: FileManager = .default) throws {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let path = databaseURL.path + suffix
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clip") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("contentHash", .text).notNull().unique()
                table.column("kind", .text).notNull()
                table.column("title", .text).notNull()
                table.column("searchText", .text).notNull()
                table.column("filePaths", .text).notNull()
                table.column("sourceBundleID", .text)
                table.column("thumbnail", .blob)
                table.column("firstCopiedAt", .datetime).notNull()
                table.column("lastCopiedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "clipRepresentation") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("clipID", .integer).notNull().indexed()
                    .references("clip", onDelete: .cascade)
                table.column("itemIndex", .integer).notNull()
                table.column("position", .integer).notNull()
                table.column("type", .text).notNull()
                table.column("data", .blob).notNull()
            }
        }
        return migrator
    }
}
