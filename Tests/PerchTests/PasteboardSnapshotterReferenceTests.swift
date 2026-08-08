import AppKit
import XCTest
@testable import Perch

@MainActor
final class PasteboardSnapshotterReferenceTests: XCTestCase {
    func testReferenceModeLeavesSourceInPlaceAndSurvivesReload() throws {
        try withReferenceSetting(true) {
            let fixture = try SnapshotterReferenceFixture()
            defer { fixture.remove() }
            let source = try fixture.makeSourceFile(named: "notes.txt")

            let results = try fixture.snapshot(source)

            let item = try XCTUnwrap(results.first?.item)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try Data(contentsOf: source), Data("payload".utf8))
            XCTAssertEqual(item.metadata.referencedFiles?["notes.txt"]?.originalPath, source.path)
            XCTAssertTrue(
                try FileManager.default.contentsOfDirectory(
                    at: item.directoryURL.appendingPathComponent("files"),
                    includingPropertiesForKeys: nil
                ).isEmpty
            )

            let reloadedStore = ItemStore(holding: fixture.holding)
            try reloadedStore.load()
            let reloadedItem = try XCTUnwrap(reloadedStore.items.first)
            XCTAssertEqual(
                try Data(contentsOf: reloadedItem.backingFileURLs()[0]),
                Data("payload".utf8)
            )
        }
    }

    func testReferenceModeDefaultsOffAndStillMovesTheSource() throws {
        try withReferenceSetting(nil) {
            let fixture = try SnapshotterReferenceFixture()
            defer { fixture.remove() }
            let source = try fixture.makeSourceFile(named: "notes.txt")

            let item = try XCTUnwrap(fixture.snapshot(source).first?.item)

            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertNil(item.metadata.referencedFiles)
            XCTAssertEqual(
                try Data(contentsOf: item.backingFileURLs()[0]),
                Data("payload".utf8)
            )
        }
    }

    func testTransformOutputIsOwnedEvenWhenReferenceModeIsEnabled() throws {
        try withReferenceSetting(true) {
            let fixture = try SnapshotterReferenceFixture()
            defer { fixture.remove() }
            let output = try fixture.makeSourceFile(named: "converted.jpg")

            let item = try PasteboardSnapshotter(holding: fixture.holding).snapshotOwnedFile(
                output,
                into: fixture.store,
                at: 0
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertNil(item.metadata.referencedFiles)
            XCTAssertEqual(item.metadata.backingFileNames, ["converted.jpg"])
            XCTAssertEqual(try Data(contentsOf: item.backingFileURLs()[0]), Data("payload".utf8))
        }
    }

    func testFilingAReferenceCopiesItsContentAndRemovesOnlyThePointer() throws {
        let fixture = try SnapshotterReferenceFixture()
        defer { fixture.remove() }
        let source = try fixture.makeSourceFile(named: "notes.txt")
        let directory = fixture.store.newItemDirectory()
        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(),
            title: "notes.txt",
            representations: [],
            backingFileNames: ["notes.txt"],
            primaryFileType: "public.plain-text",
            originPaths: nil,
            referencedFiles: ["notes.txt": ReferencedFile(url: source)]
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )
        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        fixture.store.insert(item, at: nil)
        let destination = fixture.root.appendingPathComponent("Filed", isDirectory: true)

        let filed = fixture.store.fileItems([item], into: destination)

        XCTAssertEqual(filed.map(\.lastPathComponent), ["notes.txt"])
        XCTAssertEqual(try Data(contentsOf: filed[0]), Data("payload".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(fixture.store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.url.path))
    }

    private func withReferenceSetting(
        _ value: Bool?,
        operation: () throws -> Void
    ) rethrows {
        let defaults = UserDefaults.standard
        let key = PerchSettings.referenceDroppedFiles
        let previousValue = defaults.object(forKey: key)
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        try operation()
    }
}

@MainActor
private final class SnapshotterReferenceFixture {
    let root: URL
    let holding: HoldingDirectory
    let store: ItemStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PasteboardSnapshotterReferenceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        holding = HoldingDirectory(
            root: root.appendingPathComponent("Perch", isDirectory: true)
        )
        store = ItemStore(holding: holding)
        try FileManager.default.createDirectory(
            at: holding.itemsDir,
            withIntermediateDirectories: true
        )
    }

    func makeSourceFile(named name: String) throws -> URL {
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        let source = sourceDirectory.appendingPathComponent(name, isDirectory: false)
        try Data("payload".utf8).write(to: source)
        return source
    }

    func snapshot(_ source: URL) throws -> [PasteboardSnapshotResult] {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("Perch.ReferenceTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        guard pasteboard.writeObjects([source as NSURL]) else {
            XCTFail("Could not populate test pasteboard")
            return []
        }
        defer { pasteboard.clearContents() }
        return try PasteboardSnapshotter(holding: holding).snapshot(
            pasteboard,
            into: store
        )
    }

    nonisolated func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
