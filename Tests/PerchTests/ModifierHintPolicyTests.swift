import AppKit
import XCTest
@testable import Perch

final class ModifierHintPolicyTests: XCTestCase {
    private func context(
        _ modifiers: NSEvent.ModifierFlags,
        overItem: Bool = true,
        _ configure: (inout ModifierHintPolicy.Context) -> Void = { _ in }
    ) -> ModifierHintPolicy.Context {
        var context = ModifierHintPolicy.Context()
        context.modifiers = modifiers
        context.isPointerOverItem = overItem
        context.showsGrabHandle = false
        context.hasSelectionAnchor = true
        configure(&context)
        return context
    }

    func testEachModifierMapsToItsHint() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.control, overItem: false)), .moveShelf)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.option)), .copyOut)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.command)), .toggleSelection)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.shift)), .rangeSelection)
    }

    func testNothingShowsMidGesture() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.option) { $0.isInteracting = true }), .none)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.command) { $0.isInteracting = true }), .none)
    }

    func testCombinedModifiersShowNothing() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context([.option, .command])), .none)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context([.control, .shift])), .none)
    }

    func testIrrelevantFlagsAreIgnored() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context([.option, .capsLock])), .copyOut)
    }

    func testControlNeedsModifierModeAndAMovableShelf() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.control) { $0.showsGrabHandle = true }), .none)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.control) { $0.canMoveShelf = false }), .none)
    }

    func testOptionDoesNothingWhenCopyingIsAlreadyTheDefault() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.option) { $0.copiesByDefault = true }), .none)
    }

    func testOnlyShiftNeedsAnItemUnderThePointer() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.option, overItem: false)), .copyOut)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.command, overItem: false)), .toggleSelection)
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.shift, overItem: false)), .none)
    }

    func testShiftNeedsAnAnchor() {
        XCTAssertEqual(ModifierHintPolicy.hint(for: context(.shift) { $0.hasSelectionAnchor = false }), .none)
    }

    func testRangePreviewSpansAnchorToHoveredInEitherDirection() {
        let ids = [1, 2, 3, 4, 5]
        XCTAssertEqual(ModifierHintPolicy.rangePreview(anchor: 2, hovered: 4, orderedIDs: ids), [2, 3, 4])
        XCTAssertEqual(ModifierHintPolicy.rangePreview(anchor: 4, hovered: 2, orderedIDs: ids), [2, 3, 4])
        XCTAssertEqual(ModifierHintPolicy.rangePreview(anchor: 9, hovered: 2, orderedIDs: ids), [])
    }

    func testCopyTargetsFollowTheSelectionOnlyWhenHoveringIt() {
        XCTAssertEqual(ModifierHintPolicy.copyTargets(hovered: 1, selected: [1, 2], all: [1, 2, 3]), [1, 2])
        XCTAssertEqual(ModifierHintPolicy.copyTargets(hovered: 3, selected: [1, 2], all: [1, 2, 3]), [3])
        XCTAssertEqual(ModifierHintPolicy.copyTargets(hovered: nil, selected: [1], all: [1, 2, 3]), [1, 2, 3])
    }

    func testDebouncerWaitsForAHoldAndClearsImmediately() {
        var debouncer = ModifierHintDebouncer()
        XCTAssertEqual(debouncer.update(.copyOut, now: 0), .none)
        XCTAssertEqual(debouncer.update(.copyOut, now: 0.1), .none)
        XCTAssertEqual(debouncer.update(.copyOut, now: 0.16), .copyOut)
        XCTAssertEqual(debouncer.update(.none, now: 0.2), .none)
    }

    func testDebouncerRestartsTheHoldWhenTheHintChanges() {
        var debouncer = ModifierHintDebouncer()
        _ = debouncer.update(.copyOut, now: 0)
        XCTAssertEqual(debouncer.update(.copyOut, now: 0.2), .copyOut)
        XCTAssertEqual(debouncer.update(.toggleSelection, now: 0.25), .none)
        XCTAssertEqual(debouncer.update(.toggleSelection, now: 0.41), .toggleSelection)
    }
}
