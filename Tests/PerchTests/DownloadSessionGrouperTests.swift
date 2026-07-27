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
            "Screenshot"
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

    func testFreshUniquePromiseCopyMatchesItsArrivalSource() {
        let now = Date()
        let screenshot = ArrivalFileFingerprint(
            name: "Screenshot 2026-07-27 at 10.00.00 AM.png",
            byteCount: 42_000
        )

        let paths = ArrivalCopyMatcher.matchingPaths(
            materializedFingerprints: [screenshot],
            candidates: [
                ArrivalCopyCandidate(
                    path: "/Users/test/Desktop/\(screenshot.name)",
                    fingerprint: screenshot,
                    addedAt: now.addingTimeInterval(-4)
                ),
                ArrivalCopyCandidate(
                    path: "/Users/test/Desktop/unrelated.png",
                    fingerprint: ArrivalFileFingerprint(
                        name: "unrelated.png",
                        byteCount: 42_000
                    ),
                    addedAt: now.addingTimeInterval(-1)
                )
            ],
            droppedAt: now
        )

        XCTAssertEqual(
            paths,
            ["/Users/test/Desktop/\(screenshot.name)"]
        )
    }

    func testPromiseCopyDoesNotMatchAnOldArrival() {
        let now = Date()
        let fingerprint = ArrivalFileFingerprint(name: "image.png", byteCount: 99)

        let paths = ArrivalCopyMatcher.matchingPaths(
            materializedFingerprints: [fingerprint],
            candidates: [
                ArrivalCopyCandidate(
                    path: "/Users/test/Desktop/image.png",
                    fingerprint: fingerprint,
                    addedAt: now.addingTimeInterval(
                        -(ArrivalCopyMatcher.maximumAge + 1)
                    )
                )
            ],
            droppedAt: now
        )

        XCTAssertTrue(paths.isEmpty)
    }

    func testPromiseCopyLeavesAmbiguousArrivalsAlone() {
        let now = Date()
        let fingerprint = ArrivalFileFingerprint(name: "same.png", byteCount: 99)

        let paths = ArrivalCopyMatcher.matchingPaths(
            materializedFingerprints: [fingerprint],
            candidates: [
                ArrivalCopyCandidate(
                    path: "/Users/test/Desktop/same.png",
                    fingerprint: fingerprint,
                    addedAt: now.addingTimeInterval(-1)
                ),
                ArrivalCopyCandidate(
                    path: "/Users/test/Downloads/same.png",
                    fingerprint: fingerprint,
                    addedAt: now.addingTimeInterval(-2)
                )
            ],
            droppedAt: now
        )

        XCTAssertTrue(paths.isEmpty)
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
