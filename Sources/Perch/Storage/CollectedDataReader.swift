import Foundation
import GRDB

/// One table of a Labs database, as stored, for the "See Collected Data" window.
struct CollectedTable: Equatable, Identifiable {
    let name: String
    let columns: [String]
    let rows: [[String]]
    let totalRows: Int

    var id: String { name }
}

/// Reads a Labs database read-only and renders every table's rows as text. It never
/// creates a database: a missing file means nothing has been collected.
enum CollectedDataReader {
    static let rowLimit = 500
    static let textLimit = 300

    static func read(databaseURL: URL) throws -> [CollectedTable] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        return try database.read { db in
            let names = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
            return try names.map { name in
                let quoted = name.quotedDatabaseIdentifier
                let columns = try db.columns(in: name).map(\.name)
                let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(quoted)") ?? 0
                let rows = try Row.fetchAll(
                    db, sql: "SELECT * FROM \(quoted) ORDER BY rowid DESC LIMIT \(rowLimit)"
                ).map { row in columns.map { describe(row[$0] as DatabaseValue) } }
                return CollectedTable(name: name, columns: columns, rows: rows, totalRows: total)
            }
        }
    }

    static func describe(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null:
            return "—"
        case let .int64(number):
            return String(number)
        case let .double(number):
            return String(number)
        case let .string(text):
            return text.count > textLimit ? String(text.prefix(textLimit)) + "…" : text
        case let .blob(data):
            return "<\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) of data>"
        }
    }
}
