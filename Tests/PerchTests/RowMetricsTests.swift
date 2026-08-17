import XCTest
@testable import Perch

final class RowMetricsTests: XCTestCase {
    func testLabeledRowsHugTheirTitleAndStayInsideTheLane() {
        let theme = ShelfTheme.resolve(.glass)
        let maximumWidth: CGFloat = 400

        let shortWidth = RowMetrics.itemRowWidth(
            title: "Gmail",
            theme: theme,
            showsLabels: true,
            showsAction: false,
            maximumWidth: maximumWidth
        )
        let longerWidth = RowMetrics.itemRowWidth(
            title: "Messages — Lachlan Wession",
            theme: theme,
            showsLabels: true,
            showsAction: false,
            maximumWidth: maximumWidth
        )
        let cappedWidth = RowMetrics.itemRowWidth(
            title: String(repeating: "very long filename ", count: 20),
            theme: theme,
            showsLabels: true,
            showsAction: false,
            maximumWidth: maximumWidth
        )

        XCTAssertLessThan(shortWidth, longerWidth)
        XCTAssertLessThan(longerWidth, maximumWidth)
        XCTAssertEqual(cappedWidth, maximumWidth)
    }

    func testDedicatedActionSlotDoesNotForceTheWholeLaneWidth() {
        let theme = ShelfTheme.resolve(.glass)
        let maximumWidth: CGFloat = 400
        let labelOnlyWidth = RowMetrics.itemRowWidth(
            title: "Terminal — Perch",
            theme: theme,
            showsLabels: true,
            showsAction: false,
            maximumWidth: maximumWidth
        )
        let hoveredWidth = RowMetrics.itemRowWidth(
            title: "Terminal — Perch",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            maximumWidth: maximumWidth
        )

        XCTAssertEqual(
            hoveredWidth - labelOnlyWidth,
            RowMetrics.deleteDiameter + RowMetrics.deleteTrailingInset
        )
        XCTAssertLessThan(hoveredWidth, maximumWidth)
    }

    func testLearnedRouteReservesASecondTrailingSlot() {
        let theme = ShelfTheme.resolve(.glass)
        let maximumWidth: CGFloat = 400
        let deleteOnlyWidth = RowMetrics.itemRowWidth(
            title: "invoice-april.pdf",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            maximumWidth: maximumWidth
        )
        let withRouteWidth = RowMetrics.itemRowWidth(
            title: "invoice-april.pdf",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            showsRouteAction: true,
            maximumWidth: maximumWidth
        )

        XCTAssertEqual(
            withRouteWidth - deleteOnlyWidth,
            RowMetrics.deleteDiameter + RowMetrics.trailingActionSpacing
        )
    }

    func testATrailingActionSlotHoldsEachButtonClearOfItsNeighbor() {
        let outer = RowMetrics.trailingActionCenterInset(index: 0)
        let inner = RowMetrics.trailingActionCenterInset(index: 1)

        XCTAssertEqual(
            outer,
            RowMetrics.deleteTrailingInset + RowMetrics.deleteDiameter / 2
        )
        // Centers are one pitch apart, which is also the enlarged hit width used when
        // two buttons sit side by side — so neighbouring rects touch without overlapping.
        XCTAssertEqual(
            inner - outer,
            RowMetrics.deleteDiameter + RowMetrics.trailingActionSpacing
        )
    }

    func testIconOnlyRowsRetainTheWholeInteractionLane() {
        XCTAssertEqual(
            RowMetrics.itemRowWidth(
                title: "Ignored",
                theme: ShelfTheme.resolve(.minimal),
                showsLabels: false,
                showsAction: false,
                maximumWidth: 180
            ),
            180
        )
    }

    func testPopulatedCardUsesItsWidestTitleInsteadOfTheWholeMaximum() {
        let theme = ShelfTheme.resolve(.glass)
        let maximumWidth: CGFloat = 600
        let cardWidth = RowMetrics.contentHuggingCardWidth(
            rows: [
                ("Gmail", true, false),
                ("Terminal — Perch", true, false)
            ],
            theme: theme,
            maximumWidth: maximumWidth
        )
        let expectedRowWidth = RowMetrics.itemRowWidth(
            title: "Terminal — Perch",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            maximumWidth: maximumWidth - theme.contentPadding * 2
        )

        XCTAssertEqual(
            cardWidth,
            expectedRowWidth + theme.contentPadding * 2
        )
        XCTAssertLessThan(cardWidth, maximumWidth / 2)
    }

    func testWidestTitleDefinesOneSharedCompactRowWidth() {
        let theme = ShelfTheme.resolve(.glass)
        let cardWidth = RowMetrics.contentHuggingCardWidth(
            rows: [
                ("Gmail", true, false),
                ("Terminal — Perch", true, false),
                ("Activity Monitor", true, false)
            ],
            theme: theme,
            maximumWidth: 600
        )
        let sharedRowWidth = cardWidth - theme.contentPadding * 2
        let widestTitleWidth = RowMetrics.itemRowWidth(
            title: "Terminal — Perch",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            maximumWidth: 600
        )

        XCTAssertEqual(sharedRowWidth, widestTitleWidth)
    }

    func testGhostOnlyCardMatchesTheStableAdoptedRowWidth() {
        let theme = ShelfTheme.resolve(.glass)
        let cardWidth = RowMetrics.contentHuggingCardWidth(
            rows: [("Messages — Lachlan Wession", true, false)],
            theme: theme,
            maximumWidth: 600
        )
        let ghostWidth = RowMetrics.itemRowWidth(
            title: "Messages — Lachlan Wession",
            theme: theme,
            showsLabels: true,
            showsAction: true,
            maximumWidth: 600
        )

        XCTAssertEqual(
            cardWidth,
            ghostWidth + theme.contentPadding * 2
        )
    }

    func testPendingScreenshotUsesItsPlaceholderAsAConservativeWidthEstimate() {
        let theme = ShelfTheme.resolve(.glass)
        let maximumWidth: CGFloat = 300
        let pendingWidth = RowMetrics.contentHuggingCardWidth(
            rows: [(ScreenshotNamePresentation.placeholder, true, false)],
            theme: theme,
            maximumWidth: maximumWidth
        )
        let predictedWidth = RowMetrics.contentHuggingCardWidth(
            rows: [("Messages — Lachlan Wession", true, false)],
            theme: theme,
            maximumWidth: maximumWidth
        )

        XCTAssertLessThan(pendingWidth, predictedWidth)
    }
}
