import Foundation
import XCTest
@testable import Perch

/// Isolation is declared per test method rather than on the class. `EdgeSettings` is
/// `@MainActor`, but XCTest's `setUp`/`tearDown` overrides are not, and a `@MainActor`
/// test class cannot read or write its own stored properties from them — an error on the
/// toolchain CI runs, whatever a newer local Swift may allow. Keeping the class
/// non-isolated and the saved state inside the teardown block sidesteps the clash
/// entirely, the same arrangement `FirstRunExperienceTests` uses.
final class EdgeSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // These tests drive the real standard domain, because that is where `EdgeSettings`
        // reads and writes. Capture what was there and restore it afterwards so a test run
        // never leaves the developer's own edge selection changed. `[String]` is what the
        // key actually holds and crosses into the teardown block safely; `Any?` could not.
        let savedEdges = UserDefaults.standard.array(
            forKey: PerchSettings.enabledEdges
        ) as? [String]
        UserDefaults.standard.removeObject(forKey: PerchSettings.enabledEdges)
        addTeardownBlock {
            if let savedEdges {
                UserDefaults.standard.set(savedEdges, forKey: PerchSettings.enabledEdges)
            } else {
                UserDefaults.standard.removeObject(forKey: PerchSettings.enabledEdges)
            }
        }
    }

    @MainActor
    func testAFreshInstallGetsBothSideDocks() {
        XCTAssertEqual(EdgeSettings().enabledEdges, [.left, .right])
    }

    @MainActor
    func testTheFirstRunPickerCanReplaceTheWholeSelectionAtOnce() {
        let settings = EdgeSettings()
        settings.setEnabledEdges([.left])
        XCTAssertEqual(settings.enabledEdges, [.left])
    }

    @MainActor
    func testReplacingTheSelectionRebuildsTheEdgeTabsExactlyOnce() {
        // Applying the picker's answer as a sequence of toggles would tear down and
        // reinstall every edge tab once per edge.
        let settings = EdgeSettings()
        var rebuilds = 0
        settings.onChange = { rebuilds += 1 }
        settings.setEnabledEdges([.left, .notch])
        XCTAssertEqual(rebuilds, 1)
    }

    @MainActor
    func testAnUnchangedSelectionIsNotRepublished() {
        let settings = EdgeSettings()
        var rebuilds = 0
        settings.onChange = { rebuilds += 1 }
        settings.setEnabledEdges(settings.enabledEdges)
        XCTAssertEqual(rebuilds, 0)
    }

    @MainActor
    func testAnEmptySelectionIsRefusedSoTheShelfStaysReachable() {
        let settings = EdgeSettings()
        settings.setEnabledEdges([])
        XCTAssertEqual(settings.enabledEdges, [.left, .right])
    }

    @MainActor
    func testTheChosenEdgesSurviveALaunch() {
        EdgeSettings().setEnabledEdges([.notch])
        XCTAssertEqual(EdgeSettings().enabledEdges, [.notch])
    }
}
