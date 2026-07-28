import Foundation
import XCTest
@testable import Perch

@MainActor
final class ItemStoreLoadTests: XCTestCase {
    func testUnreadableMetadataKeepsTheRestOfTheShelfAndPreservesItsFiles() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let first = try fixture.writeItem(filename: "a.png")
        let damaged = try fixture.writeItem(filename: "b.png")
        let last = try fixture.writeItem(filename: "c.png")
        try fixture.writeIndex([first, damaged, last])
        try fixture.corruptMetadata(of: damaged)

        try fixture.store.load()

        XCTAssertEqual(fixture.store.items.map(\.id), [first, last])
        XCTAssertTrue(fixture.store.isDegraded)
        XCTAssertTrue(fixture.directoryExists(damaged))
    }

    func testDegradedStoreKeepsUnreadableIDsInEveryIndexWriteAndSkipsTheSweep() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let healthy = try fixture.writeItem(filename: "a.png")
        let damaged = try fixture.writeItem(filename: "b.png")
        // Never referenced by the index: normally swept, but a degraded load must not
        // reconcile destructively against an index it could not fully resolve.
        let orphan = try fixture.writeItem(filename: "c.png")
        try fixture.writeIndex([healthy, damaged])
        try fixture.corruptMetadata(of: damaged)

        try fixture.store.load()
        XCTAssertTrue(fixture.directoryExists(orphan))

        // The write that used to be fatal: rewriting the index after a partial load.
        let added = try fixture.insertItem(filename: "d.png")

        XCTAssertEqual(try fixture.readIndex(), [added, healthy, damaged])
        XCTAssertTrue(fixture.directoryExists(damaged))
    }

    func testMissingIndexProtectsItemDirectoriesInsteadOfDiscardingThem() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let first = try fixture.writeItem(filename: "a.png")
        let second = try fixture.writeItem(filename: "b.png")

        try fixture.store.load()

        XCTAssertTrue(fixture.store.items.isEmpty)
        XCTAssertTrue(fixture.store.isDegraded)
        XCTAssertTrue(fixture.directoryExists(first))
        XCTAssertTrue(fixture.directoryExists(second))

        let added = try fixture.insertItem(filename: "c.png")
        XCTAssertEqual(try fixture.readIndex().first, added)
        XCTAssertEqual(Set(try fixture.readIndex()), [added, first, second])
    }

    func testUnreadableIndexProtectsItemDirectoriesAndStillReportsTheFailure() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let existing = try fixture.writeItem(filename: "a.png")
        try Data("not json".utf8).write(to: fixture.holding.indexFile)

        XCTAssertThrowsError(try fixture.store.load())
        XCTAssertTrue(fixture.store.isDegraded)
        XCTAssertTrue(fixture.directoryExists(existing))

        _ = try fixture.insertItem(filename: "b.png")
        XCTAssertTrue(try fixture.readIndex().contains(existing))
    }

    func testHealthyLoadStillSweepsOrphanedDirectories() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let indexed = try fixture.writeItem(filename: "a.png")
        let orphan = try fixture.writeItem(filename: "b.png")
        try fixture.writeIndex([indexed])

        try fixture.store.load()

        XCTAssertFalse(fixture.store.isDegraded)
        XCTAssertEqual(fixture.store.items.map(\.id), [indexed])
        XCTAssertFalse(fixture.directoryExists(orphan))
    }

    func testStaleIndexEntryWithNoDirectoryIsNotTreatedAsDamage() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let present = try fixture.writeItem(filename: "a.png")
        try fixture.writeIndex([present, UUID()])

        try fixture.store.load()

        XCTAssertFalse(fixture.store.isDegraded)
        XCTAssertEqual(fixture.store.items.map(\.id), [present])
    }

    func testProtectedIDIsDroppedOnceItsDirectoryIsDeleted() throws {
        let fixture = try ItemStoreLoadFixture()
        defer { fixture.remove() }

        let healthy = try fixture.writeItem(filename: "a.png")
        let damaged = try fixture.writeItem(filename: "b.png")
        try fixture.writeIndex([healthy, damaged])
        try fixture.corruptMetadata(of: damaged)
        try fixture.store.load()

        try FileManager.default.removeItem(at: fixture.holding.itemDir(damaged))
        _ = try fixture.insertItem(filename: "c.png")

        XCTAssertFalse(try fixture.readIndex().contains(damaged))
    }
}

@MainActor
private final class ItemStoreLoadFixture {
    let rootURL: URL
    let holding: HoldingDirectory
    let store: ItemStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ItemStoreLoadTests-\(UUID().uuidString)",
            isDirectory: true
        )
        holding = HoldingDirectory(root: rootURL)
        store = ItemStore(holding: holding)
        try FileManager.default.createDirectory(
            at: holding.itemsDir,
            withIntermediateDirectories: true
        )
    }

    /// Lay an item out on disk without going through the store, so `load()` sees it
    /// exactly as a previous launch would have left it.
    @discardableResult
    func writeItem(filename: String) throws -> UUID {
        let directory = store.newItemDirectory()
        try Data("payload".utf8).write(
            to: directory.url
                .appendingPathComponent("files", isDirectory: true)
                .appendingPathComponent(filename)
        )
        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: filename,
            representations: [],
            backingFileNames: [filename],
            primaryFileType: "public.png",
            originPaths: nil
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )
        return directory.id
    }

    /// Add an item through the store, which is what rewrites `index.json`.
    @discardableResult
    func insertItem(filename: String) throws -> UUID {
        let id = try writeItem(filename: filename)
        let metadata = try JSONDecoder().decode(
            ItemMetadata.self,
            from: Data(contentsOf: holding.itemDir(id).appendingPathComponent("meta.json"))
        )
        store.insert(
            StoredItem(metadata: metadata, directoryURL: holding.itemDir(id)),
            at: nil
        )
        return id
    }

    func writeIndex(_ ids: [UUID]) throws {
        try JSONEncoder().encode(ids).write(to: holding.indexFile, options: .atomic)
    }

    func readIndex() throws -> [UUID] {
        try JSONDecoder().decode([UUID].self, from: Data(contentsOf: holding.indexFile))
    }

    func corruptMetadata(of id: UUID) throws {
        try Data("{ truncated".utf8).write(
            to: holding.itemDir(id).appendingPathComponent("meta.json")
        )
    }

    func directoryExists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: holding.itemDir(id).path)
    }

    nonisolated func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
