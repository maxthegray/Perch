import Foundation
import XCTest
@testable import Perch

final class ShelfSizePresetTests: XCTestCase {
    /// The defaults, unchanged from the old Standard preset.
    func testStandardHugsContentAtTheDesignWidth() {
        XCTAssertEqual(ShelfSizePreset.standard.widthScale, 1)
        XCTAssertEqual(ShelfSizePreset.standard.heightFraction, 0)
    }

    func testMigratesAnUntouchedInstallToStandard() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1, heightFraction: 0),
            .standard
        )
    }

    /// The retired Square preset was 150% width with a small height floor. It has no
    /// successor, so it lands on the preset that shares its width.
    func testMigratesTheRetiredSquarePresetToWide() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1.5, heightFraction: 0.13),
            .wide
        )
    }

    func testMigratesTheTallPreset() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1, heightFraction: 0.8),
            .tall
        )
    }

    func testMigratesAFullHeightCustomSizeToFull() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1, heightFraction: 1),
            .full
        )
    }

    /// Height wins over width: someone who dragged both sliders up wanted a tall shelf,
    /// and `wide` cannot express that at all.
    func testHeightTakesPrecedenceOverWidthWhenBothWereRaised() {
        XCTAssertEqual(
            ShelfSizePreset.nearest(widthScale: 1.8, heightFraction: 0.7),
            .tall
        )
    }

    /// Stacking makes the card square, so the height presets are withheld from it.
    func testOnlyTheFlatPresetsSurviveStacking() {
        let stackable = ShelfSizePreset.allCases.filter(\.isAvailableWhileStacking)
        XCTAssertEqual(stackable, [.standard, .wide])
    }
}
