import AppKit
import XCTest
@testable import Perch

@MainActor
final class ShelfQuickLookTests: XCTestCase {
    func testFileItemPreviewsItsBackingFiles() throws {
        let fixture = QuickLookFixture()
        defer { fixture.remove() }
        let item = try fixture.makeItem(files: ["a.png", "b.pdf"], reps: [(.string, "ignored")])
        let urls = ShelfQuickLook.previewURLs(for: item, scratchDirectory: fixture.scratch)
        XCTAssertEqual(urls, item.backingFileURLs())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.scratch.path))
    }

    func testTextClippingIsWrittenToATextFile() throws {
        let fixture = QuickLookFixture()
        defer { fixture.remove() }
        let item = try fixture.makeItem(reps: [(.string, "Hello shelf")])
        let urls = ShelfQuickLook.previewURLs(for: item, scratchDirectory: fixture.scratch)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.pathExtension, "txt")
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "Hello shelf")
    }

    func testLinkClippingFallsBackToURLText() throws {
        let fixture = QuickLookFixture()
        defer { fixture.remove() }
        let item = try fixture.makeItem(reps: [(.URL, "https://example.com")])
        let urls = ShelfQuickLook.previewURLs(for: item, scratchDirectory: fixture.scratch)
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "https://example.com")
        XCTAssertTrue(ShelfQuickLook().canPreview(item))
    }

    func testItemWithNothingToShowIsNotPreviewable() throws {
        let fixture = QuickLookFixture()
        defer { fixture.remove() }
        let item = try fixture.makeItem(reps: [(.png, "")])
        XCTAssertEqual(ShelfQuickLook.previewURLs(for: item, scratchDirectory: fixture.scratch), [])
        XCTAssertFalse(ShelfQuickLook().canPreview(item))
    }

    func testShareItemsPreferFilesThenLinksThenText() throws {
        let fixture = QuickLookFixture()
        defer { fixture.remove() }
        let file = try fixture.makeItem(files: ["a.png"], reps: [(.string, "ignored")])
        XCTAssertEqual(ShelfSharing.shareItems(for: file) as? [URL], file.backingFileURLs())

        let link = try fixture.makeItem(reps: [(.string, "Example"), (.URL, "https://example.com")])
        XCTAssertEqual(ShelfSharing.shareItems(for: link) as? [URL], [URL(string: "https://example.com")!])

        let text = try fixture.makeItem(reps: [(.string, "Hello shelf")])
        XCTAssertEqual(ShelfSharing.shareItems(for: text) as? [String], ["Hello shelf"])

        let empty = try fixture.makeItem(reps: [(.png, "")])
        XCTAssertTrue(ShelfSharing.shareItems(for: empty).isEmpty)
    }
}

@MainActor
private struct QuickLookFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ShelfQuickLookTests-\(UUID().uuidString)", isDirectory: true)

    var scratch: URL { root.appendingPathComponent("scratch", isDirectory: true) }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeItem(
        files: [String] = [],
        reps: [(NSPasteboard.PasteboardType, String)] = []
    ) throws -> StoredItem {
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let filesDir = directory.appendingPathComponent("files", isDirectory: true)
        let repsDir = directory.appendingPathComponent("reps", isDirectory: true)
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repsDir, withIntermediateDirectories: true)
        for file in files {
            try Data("file".utf8).write(to: filesDir.appendingPathComponent(file))
        }
        var records: [RepRecord] = []
        for (index, rep) in reps.enumerated() {
            let fileName = "rep-\(index).dat"
            try Data(rep.1.utf8).write(to: repsDir.appendingPathComponent(fileName))
            records.append(RepRecord(typeIdentifier: rep.0.rawValue, fileName: fileName, isPromisePlaceholder: false))
        }
        let metadata = ItemMetadata(
            id: id,
            createdAt: Date(),
            title: "Item",
            representations: records,
            backingFileNames: files,
            primaryFileType: nil
        )
        return StoredItem(metadata: metadata, directoryURL: directory)
    }
}
