import AppKit
import SmartPerchCore
import XCTest
@testable import Perch

@MainActor
final class RouteDragSessionCoordinatorTests: XCTestCase {
    func testFolderWriteIsAuthoritativeAndRecordsBatchItemsOnce() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let endedAt = startedAt.addingTimeInterval(12.345)
        let first = UUID()
        let second = UUID()
        var recorded: [[ItemRouteEvent]] = []
        let coordinator = makeCoordinator(
            itemIDs: [first, second],
            addedAt: startedAt,
            transferMode: .copy,
            record: { recorded.append($0) }
        )

        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.finder",
                name: "Finder"
            ),
            occurredAt: endedAt
        )
        coordinator.filePromiseDidWrite(
            itemID: first,
            destinationFileURL: URL(fileURLWithPath: "/Users/test/Documents/a.pdf")
        )
        coordinator.filePromiseDidWrite(
            itemID: second,
            destinationFileURL: URL(fileURLWithPath: "/Users/test/Documents/b.pdf")
        )

        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].count, 2)
        XCTAssertEqual(Set(recorded[0].map(\.routeSessionID)).count, 1)
        XCTAssertTrue(recorded[0].allSatisfy {
            $0.destination == .folder(path: "/Users/test/Documents")
                && $0.captureMethod == .filePromiseWrite
                && $0.transferMode == .copy
                && $0.dwellTimeMilliseconds == 12_345
        })
    }

    func testApplicationEvidenceDoesNotDuplicateLaterPromiseWrite() {
        let itemID = UUID()
        var routes: [ItemRouteEvent] = []
        let coordinator = makeCoordinator(
            itemIDs: [itemID],
            record: { routes.append(contentsOf: $0) }
        )

        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.mail",
                name: "Mail"
            ),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(routes, [])

        coordinator.filePromiseDidWrite(
            itemID: itemID,
            destinationFileURL: URL(fileURLWithPath: "/Users/test/Exports/report.pdf")
        )
        coordinator.finalizePendingRoutes()

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(routes[0].destination, .folder(path: "/Users/test/Exports"))
        XCTAssertEqual(routes[0].captureMethod, .filePromiseWrite)
    }

    func testNonPromiseDropUsesTopmostApplicationObservation() {
        let itemID = UUID()
        var routes: [ItemRouteEvent] = []
        let coordinator = makeCoordinator(
            itemIDs: [itemID],
            expectsFilePromise: false,
            record: { routes = $0 }
        )

        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.Notes",
                name: "Notes"
            ),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_010)
        )

        XCTAssertEqual(routes.count, 1)
        XCTAssertEqual(
            routes[0].destination,
            .application(bundleIdentifier: "com.apple.Notes", name: "Notes")
        )
        XCTAssertEqual(routes[0].captureMethod, .applicationWindow)
    }

    func testFinderWithoutAWriteAndUnknownDestinationAreIgnored() {
        let itemID = UUID()
        var routes: [ItemRouteEvent] = []
        var coordinator = makeCoordinator(
            itemIDs: [itemID],
            record: { routes.append(contentsOf: $0) }
        )
        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.finder",
                name: "Finder"
            ),
            occurredAt: Date()
        )
        coordinator.finalizePendingRoutes()

        coordinator = makeCoordinator(
            itemIDs: [UUID()],
            expectsFilePromise: false,
            record: { routes.append(contentsOf: $0) }
        )
        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: nil,
            occurredAt: Date()
        )

        XCTAssertEqual(routes, [])
    }

    func testCancellationAndFailedDeliveryProduceNoRoutes() {
        let itemID = UUID()
        var routes: [ItemRouteEvent] = []
        var coordinator = makeCoordinator(
            itemIDs: [itemID],
            record: { routes.append(contentsOf: $0) }
        )
        coordinator.cancel()
        coordinator.filePromiseDidWrite(
            itemID: itemID,
            destinationFileURL: URL(fileURLWithPath: "/Users/test/Desktop/a.pdf")
        )
        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.finder",
                name: "Finder"
            ),
            occurredAt: Date()
        )

        coordinator = makeCoordinator(
            itemIDs: [itemID],
            record: { routes.append(contentsOf: $0) }
        )
        coordinator.filePromiseDidFail(itemID: itemID)
        coordinator.finishSuccessfulExternalDrop(
            applicationDestination: .application(
                bundleIdentifier: "com.apple.mail",
                name: "Mail"
            ),
            occurredAt: Date()
        )

        XCTAssertEqual(routes, [])
    }

    private func makeCoordinator(
        itemIDs: [UUID],
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        expectsFilePromise: Bool = true,
        transferMode: RouteTransferMode = .move,
        record: @escaping ([ItemRouteEvent]) -> Void
    ) -> RouteDragSessionCoordinator {
        RouteDragSessionCoordinator(
            items: itemIDs.map {
                RouteDragItem(
                    shelfItemID: $0,
                    addedToPerchAt: addedAt,
                    expectsFilePromise: expectsFilePromise
                )
            },
            transferMode: transferMode,
            promiseGracePeriod: .seconds(60),
            recordRoutes: record
        )
    }
}
