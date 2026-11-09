import ClipboardCore
import XCTest

final class ClipStoreTests: XCTestCase {
    private var databaseURL: URL!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("clipboard.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
    }

    func testRecentListsNewestFirst() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        try store.record(capture("one"), sourceBundleID: "a", at: date(1))
        try store.record(capture("two"), sourceBundleID: "b", at: date(2))

        XCTAssertEqual(try store.recent().map(\.title), ["two", "one"])
        XCTAssertEqual(try store.recent().first?.sourceBundleID, "b")
    }

    func testRecopyingMovesTheClipToTheTopWithoutDuplicating() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        let first = try store.record(capture("one"), sourceBundleID: "a", at: date(1))
        try store.record(capture("two"), sourceBundleID: nil, at: date(2))
        let again = try store.record(capture("one"), sourceBundleID: nil, at: date(3))

        let recent = try store.recent()
        XCTAssertEqual(first, again)
        XCTAssertEqual(recent.map(\.title), ["one", "two"])
        XCTAssertEqual(recent[0].firstCopiedAt, date(1))
        XCTAssertEqual(recent[0].lastCopiedAt, date(3))
        XCTAssertEqual(recent[0].sourceBundleID, "a", "a copy with no known source keeps the old one")
    }

    func testRecopyReplacesRepresentations() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        let id = try store.record(capture("one"), sourceBundleID: nil, at: date(1))
        let rich = try XCTUnwrap(ClipCapturePolicy.capture([ClipPasteboardItem(
            types: ["public.html", "public.utf8-plain-text"],
            data: ["public.html": Data("<i>one</i>".utf8), "public.utf8-plain-text": Data("one".utf8)]
        )]))
        try store.record(rich, sourceBundleID: nil, at: date(2))

        XCTAssertEqual(try store.representations(for: id).map(\.type), ["public.html", "public.utf8-plain-text"])
        XCTAssertEqual(try store.recent().first?.kind, .richText)
    }

    func testKeepsOnlyTheNewestClipsUpToTheLimit() throws {
        let store = try ClipStore(databaseURL: databaseURL, limit: 3)
        for index in 1...5 {
            try store.record(capture("clip \(index)"), sourceBundleID: nil, at: date(TimeInterval(index)))
        }

        XCTAssertEqual(try store.recent().map(\.title), ["clip 5", "clip 4", "clip 3"])
    }

    func testEvictedClipsLoseTheirRepresentations() throws {
        let store = try ClipStore(databaseURL: databaseURL, limit: 1)
        let old = try store.record(capture("old"), sourceBundleID: nil, at: date(1))
        try store.record(capture("new"), sourceBundleID: nil, at: date(2))

        XCTAssertEqual(try store.representations(for: old), [])
    }

    func testRepresentationsRestoreInOrder() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        let capture = try XCTUnwrap(ClipCapturePolicy.capture([
            ClipPasteboardItem(
                types: ["public.rtf", "public.utf8-plain-text"],
                data: ["public.rtf": Data("r".utf8), "public.utf8-plain-text": Data("p".utf8)]
            ),
            ClipPasteboardItem(types: ["public.utf8-plain-text"], data: ["public.utf8-plain-text": Data("q".utf8)])
        ]))
        let id = try store.record(capture, sourceBundleID: nil, at: date(1))

        XCTAssertEqual(try store.representations(for: id), capture.representations)
    }

    func testDeleteAndDeleteAll() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        let one = try store.record(capture("one"), sourceBundleID: nil, at: date(1))
        try store.record(capture("two"), sourceBundleID: nil, at: date(2))

        try store.delete(id: one)
        XCTAssertEqual(try store.recent().map(\.title), ["two"])

        try store.deleteAll()
        XCTAssertEqual(try store.recent(), [])
    }

    func testHistorySurvivesReopening() throws {
        var store: ClipStore? = try ClipStore(databaseURL: databaseURL)
        var thumbnailed = capture("kept")
        thumbnailed.thumbnail = Data([9])
        try store?.record(thumbnailed, sourceBundleID: nil, at: date(1))
        store = nil

        let reopened = try ClipStore(databaseURL: databaseURL)
        XCTAssertEqual(try reopened.recent().map(\.title), ["kept"])
        XCTAssertEqual(try reopened.recent().first?.thumbnail, Data([9]))
    }

    func testFilePathsRoundTrip() throws {
        let store = try ClipStore(databaseURL: databaseURL)
        let files = try XCTUnwrap(ClipCapturePolicy.capture(["/a/b.txt", "/c d/e.png"].map { path in
            ClipPasteboardItem(
                types: ["public.file-url"],
                data: ["public.file-url": Data(URL(fileURLWithPath: path).absoluteString.utf8)]
            )
        }))
        try store.record(files, sourceBundleID: nil, at: date(1))

        XCTAssertEqual(try store.recent().first?.filePaths, ["/a/b.txt", "/c d/e.png"])
    }

    func testRemoveFilesDeletesTheDatabase() throws {
        var store: ClipStore? = try ClipStore(databaseURL: databaseURL)
        try store?.record(capture("gone"), sourceBundleID: nil, at: date(1))
        store = nil

        try ClipStore.removeFiles(at: databaseURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(try ClipStore(databaseURL: databaseURL).recent(), [])
    }

    private func capture(_ text: String) -> ClipCapture {
        ClipCapturePolicy.capture([ClipPasteboardItem(
            types: ["public.utf8-plain-text"],
            data: ["public.utf8-plain-text": Data(text.utf8)]
        )])!
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }
}
