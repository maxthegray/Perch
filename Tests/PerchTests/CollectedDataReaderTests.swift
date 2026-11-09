import ClipboardCore
import GRDB
import XCTest
@testable import Perch

final class CollectedDataReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CollectedDataReaderTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingDatabaseReadsAsNothingAndIsNotCreated() throws {
        let url = directory.appendingPathComponent("smart-perch.sqlite")

        XCTAssertEqual(try CollectedDataReader.read(databaseURL: url), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testShowsEveryTableNewestFirstWithBlobsAsSizes() throws {
        let url = directory.appendingPathComponent("clipboard.sqlite")
        let store = try ClipStore(databaseURL: url)
        for (index, text) in ["first", "second"].enumerated() {
            let capture = try XCTUnwrap(ClipCapturePolicy.capture([ClipPasteboardItem(
                types: ["public.utf8-plain-text"], data: ["public.utf8-plain-text": Data(text.utf8)]
            )]))
            try store.record(capture, sourceBundleID: "com.example", at: Date(timeIntervalSince1970: Double(index)))
        }

        let tables = try CollectedDataReader.read(databaseURL: url)

        XCTAssertEqual(tables.map(\.name), ["clip", "clipRepresentation"])
        let clip = tables[0]
        let title = try XCTUnwrap(clip.columns.firstIndex(of: "title"))
        XCTAssertEqual(clip.totalRows, 2)
        XCTAssertEqual(clip.rows.map { $0[title] }, ["second", "first"])
        let representations = tables[1]
        let data = try XCTUnwrap(representations.columns.firstIndex(of: "data"))
        XCTAssertEqual(representations.rows.first?[data], "<6 bytes of data>")
    }

    func testCapsRowsButCountsThemAll() throws {
        let url = directory.appendingPathComponent("big.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try DatabaseQueue(path: url.path)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE event (id INTEGER PRIMARY KEY, note TEXT)")
            for index in 0..<(CollectedDataReader.rowLimit + 20) {
                try db.execute(sql: "INSERT INTO event (note) VALUES (?)", arguments: ["n\(index)"])
            }
        }

        let table = try XCTUnwrap(CollectedDataReader.read(databaseURL: url).first)

        XCTAssertEqual(table.totalRows, CollectedDataReader.rowLimit + 20)
        XCTAssertEqual(table.rows.count, CollectedDataReader.rowLimit)
    }

    func testDescribesValues() {
        XCTAssertEqual(CollectedDataReader.describe(.null), "—")
        XCTAssertEqual(CollectedDataReader.describe(42.databaseValue), "42")
        XCTAssertEqual(
            CollectedDataReader.describe(String(repeating: "x", count: 400).databaseValue).count,
            CollectedDataReader.textLimit + 1
        )
    }
}
