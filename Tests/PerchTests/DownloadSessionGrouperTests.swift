import Foundation
import XCTest
@testable import Perch

final class DownloadSessionGrouperTests: XCTestCase {
    func testThreeDownloadsWithinFiveSecondsBecomeOneSession() {
        let now = Date()
        let offers = [
            offer("one.pdf", secondsBefore: 0, now: now),
            offer("two.zip", secondsBefore: 2, now: now),
            offer("three.png", secondsBefore: 4, now: now)
        ]

        let groups = DownloadSessionGrouper.group(offers)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].map(\.name), ["one.pdf", "two.zip", "three.png"])
    }

    func testDownloadsOutsideWindowBecomeSeparateSessions() {
        let now = Date()
        let groups = DownloadSessionGrouper.group([
            offer("new.pdf", secondsBefore: 0, now: now),
            offer("old.pdf", secondsBefore: 6, now: now)
        ])

        XCTAssertEqual(groups.map(\.count), [1, 1])
    }

    func testDesktopFileDoesNotInterruptDownloadsSessionOrJoinIt() {
        let now = Date()
        let groups = DownloadSessionGrouper.group([
            offer("new.pdf", secondsBefore: 0, now: now),
            offer(
                "desktop.png",
                secondsBefore: 1,
                now: now,
                location: .desktop
            ),
            offer("second.pdf", secondsBefore: 2, now: now)
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].map(\.name), ["new.pdf", "second.pdf"])
        XCTAssertEqual(groups[1].map(\.name), ["desktop.png"])
    }

    func testOneSessionIsCappedBeforeAnotherStarts() {
        let now = Date()
        let offers = (0...DownloadSessionGrouper.maximumFilesPerSession).map { index in
            offer(
                "\(index).txt",
                secondsBefore: Double(index) / 100,
                now: now
            )
        }

        let groups = DownloadSessionGrouper.group(offers)

        XCTAssertEqual(groups.map(\.count), [
            DownloadSessionGrouper.maximumFilesPerSession,
            1
        ])
    }

    func testOfferGhostUsesSmartNameBeforeAdoption() {
        let arrival = offer("Screenshot 2026-07-26.png", secondsBefore: 0, now: Date())
        let session = ArrivalSession(id: UUID(), offers: [arrival])
        let ghost = ArrivalGhost.offer(arrival, session: session)

        XCTAssertEqual(
            ghost.displayTitle(smartName: "Terminal — Perch"),
            "Terminal — Perch"
        )
        XCTAssertEqual(
            ghost.displayTitle(smartName: nil),
            "Screenshot 2026-07-26.png"
        )
    }

    func testSessionSummaryKeepsItsBatchActionTitle() {
        let now = Date()
        let arrivals = [
            offer("one.png", secondsBefore: 0, now: now),
            offer("two.png", secondsBefore: 1, now: now)
        ]
        let session = ArrivalSession(id: UUID(), offers: arrivals)

        XCTAssertEqual(
            ArrivalGhost.summary(session, action: .expand)
                .displayTitle(smartName: "Ignored"),
            "2 new downloads"
        )
    }

    private func offer(
        _ name: String,
        secondsBefore: TimeInterval,
        now: Date,
        location: ArrivalLocation = .downloads
    ) -> ArrivalOffer {
        ArrivalOffer(
            url: URL(fileURLWithPath: "/tmp")
                .appendingPathComponent(location.rawValue)
                .appendingPathComponent(name),
            addedAt: now.addingTimeInterval(-secondsBefore),
            location: location
        )
    }
}
