import Foundation
import XCTest
@testable import Perch

@MainActor
final class ScreenshotWindowContextCaptureTests: XCTestCase {
    func testDecodesArrayScreenCaptureRectPropertyList() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [42.0, -20.0, 1_440.0, 900.0],
            format: .binary,
            options: 0
        )

        let rect = try XCTUnwrap(
            ScreenshotWindowContextCapture.captureRect(
                fromPropertyListData: data
            )
        )

        XCTAssertEqual(rect.x, 42)
        XCTAssertEqual(rect.y, -20)
        XCTAssertEqual(rect.width, 1_440)
        XCTAssertEqual(rect.height, 900)
    }

    func testDecodesStringScreenCaptureRectPropertyList() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: "{{-120, 30}, {900, 640}}",
            format: .binary,
            options: 0
        )

        let rect = try XCTUnwrap(
            ScreenshotWindowContextCapture.captureRect(
                fromPropertyListData: data
            )
        )

        XCTAssertEqual(rect.x, -120)
        XCTAssertEqual(rect.y, 30)
        XCTAssertEqual(rect.width, 900)
        XCTAssertEqual(rect.height, 640)
    }
}
