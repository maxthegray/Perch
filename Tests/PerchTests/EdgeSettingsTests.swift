import Foundation
import XCTest
@testable import Perch

@MainActor
final class EdgeSettingsTests: XCTestCase {
    private var savedEdges: Any?

    override func setUp() {
        super.setUp()
        savedEdges = UserDefaults.standard.object(forKey: PerchSettings.enabledEdges)
        UserDefaults.standard.removeObject(forKey: PerchSettings.enabledEdges)
    }

    override func tearDown() {
        if let savedEdges {
            UserDefaults.standard.set(savedEdges, forKey: PerchSettings.enabledEdges)
        } else {
            UserDefaults.standard.removeObject(forKey: PerchSettings.enabledEdges)
        }
        super.tearDown()
    }

    func testAFreshInstallGetsBothSideDocks() {
        XCTAssertEqual(EdgeSettings().enabledEdges, [.left, .right])
    }

    func testTheFirstRunPickerCanReplaceTheWholeSelectionAtOnce() {
        let settings = EdgeSettings()
        settings.setEnabledEdges([.left])
        XCTAssertEqual(settings.enabledEdges, [.left])
    }

    func testReplacingTheSelectionRebuildsTheEdgeTabsExactlyOnce() {
        // Applying the picker's answer as a sequence of toggles would tear down and
        // reinstall every edge tab once per edge.
        let settings = EdgeSettings()
        var rebuilds = 0
        settings.onChange = { rebuilds += 1 }
        settings.setEnabledEdges([.left, .notch])
        XCTAssertEqual(rebuilds, 1)
    }

    func testAnUnchangedSelectionIsNotRepublished() {
        let settings = EdgeSettings()
        var rebuilds = 0
        settings.onChange = { rebuilds += 1 }
        settings.setEnabledEdges(settings.enabledEdges)
        XCTAssertEqual(rebuilds, 0)
    }

    func testAnEmptySelectionIsRefusedSoTheShelfStaysReachable() {
        let settings = EdgeSettings()
        settings.setEnabledEdges([])
        XCTAssertEqual(settings.enabledEdges, [.left, .right])
    }

    func testTheChosenEdgesSurviveALaunch() {
        EdgeSettings().setEnabledEdges([.notch])
        XCTAssertEqual(EdgeSettings().enabledEdges, [.notch])
    }
}
