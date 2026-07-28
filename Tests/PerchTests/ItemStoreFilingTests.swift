import Foundation
import XCTest
@testable import Perch

@MainActor
final class ItemStoreFilingTests: XCTestCase {
    func testFilingMovesBackingFilesAndTakesTheItemOffTheShelf() throws {
        let fixture = try ItemStoreFilingFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(filenames: ["invoice.pdf"])
        let filed = fixture.store.fileItems([item], into: fixture.destinationURL)

        XCTAssertEqual(filed.map(\.lastPathComponent), ["invoice.pdf"])
        XCTAssertEqual(try Data(contentsOf: filed[0]), Data("payload".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: item.backingFileURLs()[0].path)
        )
        XCTAssertTrue(fixture.store.items.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: item.directoryURL.path)
        )
    }

    func testFilingNeverOverwritesAFileAlreadyInTheDestination() throws {
        let fixture = try ItemStoreFilingFixture()
        defer { fixture.remove() }

        let occupant = fixture.destinationURL
            .appendingPathComponent("invoice.pdf", isDirectory: false)
        try FileManager.default.createDirectory(
            at: fixture.destinationURL,
            withIntermediateDirectories: true
        )
        try Data("existing".utf8).write(to: occupant)

        let item = try fixture.makeItem(filenames: ["invoice.pdf"])
        let filed = fixture.store.fileItems([item], into: fixture.destinationURL)

        XCTAssertEqual(filed.map(\.lastPathComponent), ["invoice-2.pdf"])
        XCTAssertEqual(try Data(contentsOf: occupant), Data("existing".utf8))
    }

    func testAMultiFileItemLeavesTheShelfOnlyWithAllOfItsFiles() throws {
        let fixture = try ItemStoreFilingFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(filenames: ["a.txt", "b.txt", "c.txt"])
        let filed = fixture.store.fileItems([item], into: fixture.destinationURL)

        XCTAssertEqual(
            filed.map(\.lastPathComponent).sorted(),
            ["a.txt", "b.txt", "c.txt"]
        )
        XCTAssertTrue(fixture.store.items.isEmpty)
    }

    /// A destination Perch cannot write to must cost the user nothing: the files stay
    /// in the holding directory and the row stays on the shelf.
    func testAnUnusableDestinationLeavesTheItemUntouched() throws {
        let fixture = try ItemStoreFilingFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(filenames: ["invoice.pdf"])
        // A path whose parent is a regular file can never become a directory.
        let blocker = fixture.rootURL.appendingPathComponent("blocker", isDirectory: false)
        try Data("not a directory".utf8).write(to: blocker)

        let filed = fixture.store.fileItems(
            [item],
            into: blocker.appendingPathComponent("Filed", isDirectory: true)
        )

        XCTAssertTrue(filed.isEmpty)
        XCTAssertEqual(fixture.store.items.map(\.id), [item.id])
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: item.backingFileURLs()[0].path)
        )
    }

    func testFiledPathsAreReportedSoTheyAreNotOfferedBackAsFreshArrivals() throws {
        let fixture = try ItemStoreFilingFixture()
        defer { fixture.remove() }

        var reported: [URL] = []
        fixture.store.onFilesRestored = { reported = $0 }

        let item = try fixture.makeItem(filenames: ["invoice.pdf"])
        fixture.store.fileItems([item], into: fixture.destinationURL)

        XCTAssertEqual(reported.map(\.lastPathComponent), ["invoice.pdf"])
    }
}

@MainActor
private final class ItemStoreFilingFixture {
    let rootURL: URL
    let destinationURL: URL
    let holding: HoldingDirectory
    let store: ItemStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ItemStoreFilingTests-\(UUID().uuidString)",
            isDirectory: true
        )
        destinationURL = rootURL.appendingPathComponent("Filed", isDirectory: true)
        holding = HoldingDirectory(root: rootURL)
        store = ItemStore(holding: holding)
        try FileManager.default.createDirectory(
            at: holding.itemsDir,
            withIntermediateDirectories: true
        )
    }

    func makeItem(filenames: [String]) throws -> StoredItem {
        let directory = store.newItemDirectory()
        let filesDirectory = directory.url
            .appendingPathComponent("files", isDirectory: true)
        for filename in filenames {
            try Data("payload".utf8).write(
                to: filesDirectory.appendingPathComponent(filename)
            )
        }

        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: filenames[0],
            representations: [],
            backingFileNames: filenames,
            primaryFileType: "public.data",
            originPaths: nil
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )

        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        store.insert(item, at: nil)
        return item
    }

    nonisolated func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
