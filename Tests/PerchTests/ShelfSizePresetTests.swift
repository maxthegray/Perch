import Foundation
import XCTest
@testable import Perch

final class ShelfSizePresetTests: XCTestCase {
    /// The defaults, unchanged from the old Standard preset.
    func testStandardHugsContentAtTheDesignWidth() {
        XCTAssertEqual(ShelfSizePreset.standard.widthScale, 1)
        XCTAssertEqual(ShelfSizePreset.standard.heightFraction, 0)
    }

    /// Full is Tall's height at Square's width — a thicker Tall, not a bigger everything.
    func testFullIsTallAtSquaresWidth() {
        XCTAssertEqual(ShelfSizePreset.full.widthScale, ShelfSizePreset.square.widthScale)
        XCTAssertEqual(ShelfSizePreset.full.heightFraction, ShelfSizePreset.tall.heightFraction)
        XCTAssertGreaterThan(ShelfSizePreset.full.widthScale, ShelfSizePreset.tall.widthScale)
    }

    /// Square has to resolve to a card as tall as it is wide, so its height fraction is
    /// the one that depends on the display rather than being a fixed constant.
    func testSquareIsShorterThanTallButWiderThanStandard() {
        XCTAssertGreaterThan(ShelfSizePreset.square.heightFraction, 0)
        XCTAssertLessThan(
            ShelfSizePreset.square.heightFraction,
            ShelfSizePreset.tall.heightFraction
        )
        XCTAssertGreaterThan(
            ShelfSizePreset.square.widthScale,
            ShelfSizePreset.standard.widthScale
        )
    }

    // MARK: - Migrating off the sliders

    func testMigratesAnUntouchedInstallToStandard() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1, heightFraction: 0),
            .standard
        )
    }

    /// The old Square was 150% width with a small height floor.
    func testMigratesTheOldSquarePreset() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1.5, heightFraction: 0.13),
            .square
        )
    }

    func testMigratesTheOldTallPreset() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1, heightFraction: 0.8),
            .tall
        )
    }

    /// Wide and tall together is what Full now is.
    func testMigratesAWideTallCustomSizeToFull() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1.8, heightFraction: 0.7),
            .full
        )
    }

    /// A custom width with no height floor keeps the width it had.
    func testMigratesAWideShortCustomSizeToSquare() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1.6, heightFraction: 0),
            .square
        )
    }
}
