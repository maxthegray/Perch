import ClipboardCore
import XCTest
@testable import Perch

final class ClipRowDetailTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // a Friday, 08:00 UTC

    func testRecentAges() {
        XCTAssertEqual(ClipRowDetail.age(of: now.addingTimeInterval(-20), now: now, calendar: calendar), "Just now")
        XCTAssertEqual(ClipRowDetail.age(of: now.addingTimeInterval(-150), now: now, calendar: calendar), "2m ago")
        XCTAssertEqual(ClipRowDetail.age(of: now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar), "3h ago")
        XCTAssertEqual(ClipRowDetail.age(of: now.addingTimeInterval(5), now: now, calendar: calendar), "Just now")
    }

    func testOlderClipsSayYesterday() {
        XCTAssertEqual(ClipRowDetail.age(of: now.addingTimeInterval(-14 * 3600), now: now, calendar: calendar), "Yesterday")
    }

    func testTextShowsItsAppAndAge() {
        let clip = summary(kind: .text, paths: [], copied: now.addingTimeInterval(-120))
        XCTAssertEqual(ClipRowDetail.subtitle(for: clip, appName: "Chrome", now: now, calendar: calendar), "Chrome · 2m ago")
        XCTAssertEqual(ClipRowDetail.subtitle(for: clip, appName: nil, now: now, calendar: calendar), "2m ago")
    }

    func testFilesShowTheirFolderOrCount() {
        let one = summary(kind: .file, paths: ["/Users/me/Desktop/a.pdf"], copied: now)
        let many = summary(kind: .file, paths: ["/a", "/b", "/c"], copied: now)
        XCTAssertEqual(ClipRowDetail.subtitle(for: one, appName: "Finder", now: now, calendar: calendar), "Desktop · Just now")
        XCTAssertEqual(ClipRowDetail.subtitle(for: many, appName: "Finder", now: now, calendar: calendar), "3 files · Just now")
    }

    private func summary(kind: ClipKind, paths: [String], copied: Date) -> ClipSummary {
        ClipSummary(
            id: 1, kind: kind, title: "t", searchText: "t", filePaths: paths, sourceBundleID: nil,
            thumbnail: nil, firstCopiedAt: copied, lastCopiedAt: copied
        )
    }
}
