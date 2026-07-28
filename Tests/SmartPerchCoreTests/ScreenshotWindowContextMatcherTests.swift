import XCTest
@testable import SmartPerchCore

final class ScreenshotWindowContextMatcherTests: XCTestCase {
    func testForegroundWindowWinsOverLargerCoveredBackgroundWindow() throws {
        let capture = rect(50, 40, 900, 700)
        let windows = [
            window(
                pid: 10,
                bundle: "com.apple.ActivityMonitor",
                name: "Activity Monitor",
                title: "Activity Monitor",
                frame: rect(75, 60, 850, 660),
                z: 0
            ),
            window(
                pid: 20,
                bundle: "com.google.Chrome",
                name: "Google Chrome",
                title: "Gmail",
                frame: rect(0, 0, 1_440, 900),
                z: 1
            )
        ]

        let match = try XCTUnwrap(
            ScreenshotWindowContextMatcher.match(
                captureRect: capture,
                windows: windows,
                capturedAtMilliseconds: 123
            )
        )

        XCTAssertEqual(match.ownerName, "Activity Monitor")
        XCTAssertEqual(match.ownerBundleIdentifier, "com.apple.ActivityMonitor")
        XCTAssertGreaterThan(match.visibleCoverage, 0.8)
    }

    func testAdjacentWindowsFromSameAppAreCombined() throws {
        let capture = rect(0, 0, 1_000, 600)
        let windows = [
            window(
                pid: 30,
                bundle: "com.google.Chrome",
                name: "Google Chrome",
                title: "Left",
                frame: rect(0, 0, 500, 600),
                z: 0
            ),
            window(
                pid: 30,
                bundle: "com.google.Chrome",
                name: "Google Chrome",
                title: "Right",
                frame: rect(500, 0, 500, 600),
                z: 1
            )
        ]

        let match = try XCTUnwrap(
            ScreenshotWindowContextMatcher.match(
                captureRect: capture,
                windows: windows,
                capturedAtMilliseconds: 123
            )
        )

        XCTAssertEqual(match.ownerName, "Google Chrome")
        XCTAssertEqual(match.visibleCoverage, 1, accuracy: 0.001)
    }

    func testEvenSplitAcrossDifferentAppsIsTooAmbiguous() {
        let capture = rect(0, 0, 1_000, 600)
        let windows = [
            window(
                pid: 40,
                bundle: "com.apple.ActivityMonitor",
                name: "Activity Monitor",
                title: nil,
                frame: rect(0, 0, 500, 600),
                z: 0
            ),
            window(
                pid: 50,
                bundle: "com.apple.finder",
                name: "Finder",
                title: "Downloads",
                frame: rect(500, 0, 500, 600),
                z: 1
            )
        ]

        XCTAssertNil(
            ScreenshotWindowContextMatcher.match(
                captureRect: capture,
                windows: windows,
                capturedAtMilliseconds: 123
            )
        )
    }

    private func rect(
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) -> ScreenshotScreenRect {
        ScreenshotScreenRect(x: x, y: y, width: width, height: height)
    }

    private func window(
        pid: Int,
        bundle: String,
        name: String,
        title: String?,
        frame: ScreenshotScreenRect,
        z: Int
    ) -> ScreenshotWindowSnapshot {
        ScreenshotWindowSnapshot(
            processIdentifier: pid,
            bundleIdentifier: bundle,
            ownerName: name,
            windowTitle: title,
            frame: frame,
            zIndex: z
        )
    }
}
