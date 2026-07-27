import Foundation
import XCTest
@testable import Perch

@MainActor
final class ItemStoreRenameTests: XCTestCase {
    func testRenameUpdatesBackingFileMetadataAndOriginMapping() throws {
        let fixture = try ItemStoreRenameFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(
            filename: "Screenshot.png",
            originPath: "/Users/test/Desktop/Screenshot.png"
        )
        let renamedItem = try fixture.store.renameSingleBackingFile(
            of: item,
            to: "smart-perch-invoice.png"
        )

        XCTAssertEqual(renamedItem.metadata.title, "smart-perch-invoice.png")
        XCTAssertEqual(
            renamedItem.metadata.backingFileNames,
            ["smart-perch-invoice.png"]
        )
        XCTAssertEqual(
            renamedItem.metadata.originPaths,
            ["smart-perch-invoice.png": "/Users/test/Desktop/Screenshot.png"]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: item.backingFileURLs()[0].path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: renamedItem.backingFileURLs()[0].path
            )
        )

        let persisted = try JSONDecoder().decode(
            ItemMetadata.self,
            from: Data(
                contentsOf: item.directoryURL.appendingPathComponent("meta.json")
            )
        )
        XCTAssertEqual(persisted, renamedItem.metadata)
        XCTAssertEqual(fixture.store.items.first?.metadata, renamedItem.metadata)
    }

    func testRenamePreservesExtensionAndDoesNotOverwriteCollision() throws {
        let fixture = try ItemStoreRenameFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(filename: "Screenshot.png")
        let collision = item.directoryURL
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent("invoice.png")
        try Data("existing".utf8).write(to: collision)

        let renamedItem = try fixture.store.renameSingleBackingFile(
            of: item,
            to: "invoice.png"
        )

        XCTAssertEqual(renamedItem.metadata.backingFileNames, ["invoice-2.png"])
        XCTAssertEqual(try Data(contentsOf: collision), Data("existing".utf8))
        XCTAssertThrowsError(
            try fixture.store.renameSingleBackingFile(
                of: renamedItem,
                to: "invoice.jpg"
            )
        ) { error in
            XCTAssertEqual(error as? ItemStoreRenameError, .extensionChanged)
        }
    }

    /// On a case-insensitive volume the destination "already exists" — it is the source
    /// file itself — so the collision check used to hand back `Photo-2.png`.
    func testCaseOnlyRenameKeepsTheRequestedNameWithoutASuffix() throws {
        let fixture = try ItemStoreRenameFixture()
        defer { fixture.remove() }

        let item = try fixture.makeItem(filename: "photo.png")
        let renamedItem = try fixture.store.renameSingleBackingFile(
            of: item,
            to: "Photo.png"
        )

        XCTAssertEqual(renamedItem.metadata.backingFileNames, ["Photo.png"])
        XCTAssertEqual(
            try fixture.backingFileNamesOnDisk(of: renamedItem),
            ["Photo.png"]
        )
        XCTAssertEqual(
            try Data(contentsOf: renamedItem.backingFileURLs()[0]),
            Data("screenshot".utf8)
        )
    }
}

@MainActor
private final class ItemStoreRenameFixture {
    let rootURL: URL
    let holding: HoldingDirectory
    let store: ItemStore

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ItemStoreRenameTests-\(UUID().uuidString)",
            isDirectory: true
        )
        holding = HoldingDirectory(root: rootURL)
        store = ItemStore(holding: holding)
        try FileManager.default.createDirectory(
            at: holding.itemsDir,
            withIntermediateDirectories: true
        )
    }

    func makeItem(
        filename: String,
        originPath: String? = nil
    ) throws -> StoredItem {
        let directory = store.newItemDirectory()
        let fileURL = directory.url
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(filename)
        try Data("screenshot".utf8).write(to: fileURL)

        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            title: filename,
            representations: [],
            backingFileNames: [filename],
            primaryFileType: "public.png",
            originPaths: originPath.map { [filename: $0] }
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )

        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        store.insert(item, at: nil)
        return item
    }

    /// The real on-disk names, which `fileExists` cannot distinguish on a
    /// case-insensitive volume.
    func backingFileNamesOnDisk(of item: StoredItem) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: item.directoryURL.appendingPathComponent("files", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        .map(\.lastPathComponent)
        .sorted()
    }

    nonisolated func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
