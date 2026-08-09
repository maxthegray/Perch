import AppKit
import XCTest
@testable import Perch

final class MergePDFReorderPolicyTests: XCTestCase {
    func testMoveReordersDocumentsAtTheTargetPosition() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            MergePDFReorderPolicy.move(
                [first, second, third],
                itemID: first,
                to: 1
            ),
            [second, first, third]
        )
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
        let merge = try XCTUnwrap(buttons.first { $0.title == "Merge PDF" })
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
        XCTAssertEqual(window.defaultButtonCell?.title, "Merge PDF")
        window.contentView?.layoutSubtreeIfNeeded()
        let reorderView = try XCTUnwrap(
            descendants(of: controllerView(in: window)).first { $0 is MergePDFReorderView }
                as? MergePDFReorderView
        )
        XCTAssertEqual(reorderView.itemCount, 2)
        XCTAssertGreaterThan(reorderView.frame.width, 0)
        XCTAssertGreaterThan(reorderView.frame.height, 0)
        window.close()
        XCTAssertFalse(didConfirm)
    }

    func testLiveReorderMovesRowsAndPublishesTheNewOrder() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let view = MergePDFReorderView()
        view.configure([first, second, third].map {
            MergePDFReorderEntry(id: $0, image: NSImage(), title: $0.uuidString)
        })
        var publishedOrder: [UUID] = []
        view.onOrderChange = { publishedOrder = $0 }

        view.moveItem(first, to: 2, animated: false)

        XCTAssertEqual(view.orderedItemIDs, [second, third, first])
        XCTAssertEqual(publishedOrder, [second, third, first])
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
