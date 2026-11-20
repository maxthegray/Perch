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
            arrivals: ["12:00:01  desktop  revealed"]
        )

        XCTAssertTrue(report.contains("FAIL  Desktop folder"))
        XCTAssertTrue(report.contains("Blocked."))
        XCTAssertTrue(report.contains("ok    Launch at login"))
        XCTAssertTrue(report.contains("12:00:00  boom"))
        XCTAssertTrue(report.contains("arrivals (1)\n12:00:01  desktop  revealed"))
    }

    func testLogKeepsOnlyTheNewestEntries() {
        for index in 0..<250 { NSLog("filler \(index)") }
        XCTAssertEqual(PerchLog.recent.count, 200)
        XCTAssertEqual(PerchLog.recent.last?.message, "filler 249")
    }

    func testArrivalTraceStaysOutOfTheErrorLog() {
        let marker = UUID().uuidString
        PerchLog.arrivals.record("desktop  not revealed, shelf is on the strip \(marker)")

        XCTAssertTrue(Diagnostics.recentArrivals().contains { $0.contains(marker) })
        XCTAssertFalse(PerchLog.recent.contains { $0.message.contains(marker) })
    }
}
