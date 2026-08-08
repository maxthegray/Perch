import AppKit
import XCTest
@testable import Perch

final class MergePDFReorderPolicyTests: XCTestCase {
    func testMoveReordersDocumentsAtTheProposedInsertionPoint() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            MergePDFReorderPolicy.move(
                [first, second, third],
                itemID: first,
                to: 3
            ),
            [second, third, first]
        )
        XCTAssertEqual(
            MergePDFReorderPolicy.move(
                [first, second, third],
                itemID: third,
                to: 0
            ),
            [third, first, second]
        )
    }

    func testPageCountBadgeUsesDocumentLanguage() {
        XCTAssertEqual(MergePDFPageCountPresentation.badge(for: 1), "1 page")
        XCTAssertEqual(MergePDFPageCountPresentation.badge(for: 12), "12 pages")
        XCTAssertNil(MergePDFPageCountPresentation.badge(for: nil))
    }
}

@MainActor
final class MergePDFViewControllerTests: XCTestCase {
    func testKeyboardShortcutsAndCancelDoNotConfirm() throws {
        let controller = MergePDFViewController()
        var didCancel = false
        var didConfirm = false
        controller.onCancel = { didCancel = true }
        controller.onMerge = { _ in didConfirm = true }
        _ = controller.view

        let buttons = descendants(of: controller.view).compactMap { $0 as? NSButton }
        let merge = try XCTUnwrap(buttons.first { $0.title == "Merge" })
        let cancel = try XCTUnwrap(buttons.first { $0.title == "Cancel" })

        XCTAssertEqual(merge.keyEquivalent, "\r")
        XCTAssertEqual(cancel.keyEquivalent, "\u{1b}")
        controller.cancelOperation(nil)
        XCTAssertTrue(didCancel)
        XCTAssertFalse(didConfirm)
    }

    func testWindowIsKeyCapableAndClosingDoesNotConfirm() throws {
        let controller = MergePDFWindowController()
        var didConfirm = false
        controller.show(items: [makeItem(title: "First"), makeItem(title: "Second")]) { _ in
            didConfirm = true
        }
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentViewController is MergePDFViewController
        })

        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.defaultButtonCell?.title, "Merge")
        window.contentView?.layoutSubtreeIfNeeded()
        let collectionView = try XCTUnwrap(
            descendants(of: controllerView(in: window)).first { $0 is NSCollectionView }
                as? NSCollectionView
        )
        XCTAssertEqual(collectionView.numberOfItems(inSection: 0), 2)
        XCTAssertGreaterThan(collectionView.frame.width, 0)
        XCTAssertGreaterThan(collectionView.frame.height, 0)
        window.close()
        XCTAssertFalse(didConfirm)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    private func controllerView(in window: NSWindow) -> NSView {
        window.contentViewController!.view
    }

    private func makeItem(title: String) -> StoredItem {
        let id = UUID()
        return StoredItem(
            metadata: ItemMetadata(
                id: id,
                createdAt: Date(),
                title: title,
                representations: [],
                backingFileNames: [],
                primaryFileType: "com.adobe.pdf",
                originPaths: nil
            ),
            directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(
                id.uuidString,
                isDirectory: true
            )
        )
    }
}
