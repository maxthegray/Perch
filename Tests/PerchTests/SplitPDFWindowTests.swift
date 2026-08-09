import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Perch

@MainActor
final class SplitPDFViewControllerTests: XCTestCase {
    func testSplitSelectionUpdatesSummaryAndConfirmsPlan() throws {
        let fixture = try SplitPDFTestFixture(pageCount: 4)
        defer { fixture.remove() }
        let controller = SplitPDFViewController()
        var confirmedPlan: PDFSplitPlan?
        controller.onSplit = { confirmedPlan = $0 }

        XCTAssertTrue(controller.setItem(fixture.item))
        let buttons = descendants(of: controller.view).compactMap { $0 as? NSButton }
        let split = try XCTUnwrap(buttons.first { $0.title == "Split" })
        let cancel = try XCTUnwrap(buttons.first { $0.title == "Cancel" })
        let labels = descendants(of: controller.view).compactMap { $0 as? NSTextField }

        XCTAssertFalse(split.isEnabled)
        XCTAssertEqual(split.keyEquivalent, "\r")
        XCTAssertEqual(cancel.keyEquivalent, "\u{1b}")
        XCTAssertTrue(labels.contains { $0.stringValue == "1 PDF" })

        controller.pageArrangementView.toggleBreak(after: 2)

        XCTAssertTrue(split.isEnabled)
        XCTAssertTrue(labels.contains { $0.stringValue == "2 PDFs" })
        split.performClick(nil)
        XCTAssertEqual(confirmedPlan?.breaksAfterPages, [2])
    }

    func testPageArrangementPublishesOnlyValidBreaks() {
        let view = SplitPDFPagesView()
        view.configure((1...3).map {
            SplitPDFPageEntry(pageNumber: $0, image: NSImage())
        }, breaksAfterPages: [])
        var published: Set<Int> = []
        view.onBreaksChange = { published = $0 }

        view.toggleBreak(after: 0)
        view.toggleBreak(after: 3)
        XCTAssertTrue(published.isEmpty)

        view.toggleBreak(after: 1)
        view.toggleBreak(after: 2)
        XCTAssertEqual(published, [1, 2])
        XCTAssertGreaterThan(view.requiredHeight, 3 * 84)

        view.toggleBreak(after: 1)
        XCTAssertEqual(published, [2])
    }

    func testWindowFitsPagesAndClosingDoesNotConfirm() throws {
        let fixture = try SplitPDFTestFixture(pageCount: 3)
        defer { fixture.remove() }
        let controller = SplitPDFWindowController()
        var didConfirm = false
        controller.show(item: fixture.item) { _, _ in didConfirm = true }
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentViewController is SplitPDFViewController
        })

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.defaultButtonCell?.title, "Split")
        let contentController = try XCTUnwrap(
            window.contentViewController as? SplitPDFViewController
        )
        XCTAssertEqual(contentController.pageCount, 3)
        window.close()
        XCTAssertFalse(didConfirm)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class SplitPDFTestFixture {
    let root: URL
    let item: StoredItem

    init(pageCount: Int) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SplitPDFWindowTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let filesDirectory = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(
            at: filesDirectory,
            withIntermediateDirectories: true
        )
        let pdfURL = filesDirectory.appendingPathComponent("Document.pdf")
        let document = PDFDocument()
        for pageNumber in 0..<pageCount {
            let size = NSSize(width: 160 + CGFloat(pageNumber), height: 220)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()
            guard let page = PDFPage(image: image) else {
                throw SplitPDFTestError.couldNotCreatePage
            }
            document.insert(page, at: document.pageCount)
        }
        guard document.write(to: pdfURL) else {
            throw SplitPDFTestError.couldNotWriteDocument
        }

        let id = UUID()
        item = StoredItem(
            metadata: ItemMetadata(
                id: id,
                createdAt: Date(),
                title: "Document.pdf",
                representations: [],
                backingFileNames: ["Document.pdf"],
                primaryFileType: UTType.pdf.identifier,
                originPaths: nil
            ),
            directoryURL: root
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum SplitPDFTestError: Error {
    case couldNotCreatePage
    case couldNotWriteDocument
}
