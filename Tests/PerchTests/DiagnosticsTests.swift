import XCTest
@testable import Perch

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testLoggedFailuresReachTheReport() {
        let marker = UUID().uuidString
        NSLog("Perch could not reach test target \(marker)")
        NSLog("Perch loaded 3 stored item(s) \(marker)")

        let errors = Diagnostics.recentErrors(limit: 200).filter { $0.contains(marker) }

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].hasSuffix("Perch could not reach test target \(marker)"))
    }

    func testReportListsEveryCheckAndError() {
        let checks = [
            DiagnosticCheck(title: "Desktop folder", status: .problem, detail: "Blocked."),
            DiagnosticCheck(title: "Launch at login", status: .ok, detail: "On.")
        ]
        let report = Diagnostics.report(
            checks: checks,
            errors: ["12:00:00  boom"],
            arrivals: ["12:00:01  desktop  revealed"],
            actions: ["12:00:02  shelf turned solid"]
        )

        XCTAssertTrue(report.contains("FAIL  Desktop folder"))
        XCTAssertTrue(report.contains("Blocked."))
        XCTAssertTrue(report.contains("ok    Launch at login"))
        XCTAssertTrue(report.contains("12:00:00  boom"))
        XCTAssertTrue(report.contains("arrivals (1)\n12:00:01  desktop  revealed"))
        XCTAssertTrue(report.contains("actions (1)\n12:00:02  shelf turned solid"))
    }

    func testLogKeepsOnlyTheNewestEntries() {
        for index in 0..<250 { NSLog("filler \(index)") }
        XCTAssertEqual(PerchLog.recent.count, 200)
        XCTAssertEqual(PerchLog.recent.last?.message, "filler 249")
    }

    func testAgesReadAtAGlance() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(Diagnostics.age(of: nil, now: now), "none")
        XCTAssertEqual(Diagnostics.age(of: now.addingTimeInterval(-30), now: now), "30s")
        XCTAssertEqual(Diagnostics.age(of: now.addingTimeInterval(-600), now: now), "10m")
        XCTAssertEqual(Diagnostics.age(of: now.addingTimeInterval(-7 * 86400), now: now), "7d")
        XCTAssertEqual(Diagnostics.age(of: now.addingTimeInterval(5), now: now), "in 5s")
    }

    func testSettingsSnapshotKeepsScalarsAndDropsPathDictionaries() {
        let suite = "PerchTests.Diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "Perch.RevealOnHover")
        defaults.set(2, forKey: "Perch.SizePreset")
        defaults.set(["left", "right"], forKey: "Perch.EnabledEdges")
        defaults.set(["/Users/x/Downloads/a.png": Date()], forKey: "Perch.ArrivalDismissed")

        let snapshot = Diagnostics.settingsSnapshot(defaults: defaults)

        XCTAssertTrue(snapshot.contains("RevealOnHover=true"))
        XCTAssertTrue(snapshot.contains("SizePreset=2"))
        XCTAssertTrue(snapshot.contains("EnabledEdges=left,right"))
        XCTAssertFalse(snapshot.contains { $0.hasPrefix("ArrivalDismissed") })
    }

    func testFormRequestEncodesEveryAnswer() throws {
        let form = ProblemReportForm(
            formID: "FORM",
            whatHappenedEntry: "entry.1",
            reportEntry: "entry.2",
            versionEntry: "entry.3"
        )
        let request = form.request(whatHappened: "it broke & stuff", report: "ok  a=b", version: "1.0")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        XCTAssertEqual(request.url?.absoluteString, "https://docs.google.com/forms/d/e/FORM/formResponse")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body, "entry.1=it%20broke%20%26%20stuff&entry.2=ok%20%20a%3Db&entry.3=1.0")
    }

    func testArrivalTraceStaysOutOfTheErrorLog() {
        let marker = UUID().uuidString
        PerchLog.arrivals.record("desktop  not revealed, shelf is on the strip \(marker)")

        XCTAssertTrue(Diagnostics.recentArrivals().contains { $0.contains(marker) })
        XCTAssertFalse(PerchLog.recent.contains { $0.message.contains(marker) })
    }

    func testSettingsChangesNameOnlyWhatTheUserChanged() {
        let old = SettingsChangeLog.values(["RevealOnHover=true", "ShelfMoveCount=1", "SizePreset=2"])
        let new = SettingsChangeLog.values(["RevealOnHover=false", "ShelfMoveCount=2", "PeekOnHover=true"])

        XCTAssertEqual(SettingsChangeLog.changes(from: old, to: new), [
            "setting changed: PeekOnHover=true",
            "setting changed: RevealOnHover=false",
            "setting changed: SizePreset=(cleared)"
        ])
    }

    func testDragOutActionsReadPlainly() {
        XCTAssertEqual(
            ShelfHostView.dragOutAction(count: 2, operation: .copy, isMove: true, returnedToPerch: false, destination: "Finder"),
            "dragged out 2 item(s) (move) to Finder"
        )
        XCTAssertEqual(
            ShelfHostView.dragOutAction(count: 1, operation: .delete, isMove: true, returnedToPerch: false),
            "dragged 1 item(s) to the Trash"
        )
        XCTAssertEqual(
            ShelfHostView.dragOutAction(count: 1, operation: [], isMove: false, returnedToPerch: false),
            "drag out of 1 item(s) canceled"
        )
    }
}
