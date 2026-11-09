@testable import ClipboardCore
import XCTest

final class ClipSearchTests: XCTestCase {
    private let clips = [
        summary(1, "git push origin main"),
        summary(2, "Café menu"),
        summary(3, "gopher", searchText: "gopher\nsecond line mentions push"),
        summary(4, "unrelated")
    ]

    func testEmptyQueryKeepsEverythingInOrder() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "  ").map(\.id), [1, 2, 3, 4])
    }

    func testSubstringMatchesSearchTheFullText() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "push").map(\.id), [1, 3])
    }

    func testCaseAndDiacriticsAreIgnored() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "CAFE").map(\.id), [2])
    }

    func testSubsequenceMatchesRankAfterSubstringMatches() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "gpe").map(\.id), [3])
        XCTAssertEqual(ClipSearch.filter(clips, query: "go").map(\.id), [3, 1])
    }

    func testNoMatchReturnsNothing() {
        XCTAssertEqual(ClipSearch.filter(clips, query: "zzz"), [])
    }

    func testIsSubsequence() {
        XCTAssertTrue(ClipSearch.isSubsequence("gpm", of: "git push main"))
        XCTAssertFalse(ClipSearch.isSubsequence("mpg", of: "git push main"))
    }

    private static func summary(_ id: Int64, _ title: String, searchText: String? = nil) -> ClipSummary {
        ClipSummary(
            id: id, kind: .text, title: title, searchText: searchText ?? title, filePaths: [],
            sourceBundleID: nil, thumbnail: nil, firstCopiedAt: .distantPast, lastCopiedAt: .distantPast
        )
    }
}
