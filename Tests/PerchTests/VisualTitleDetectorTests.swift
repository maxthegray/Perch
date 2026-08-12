import SmartPerchCore
import XCTest
@testable import Perch

final class VisualTitleDetectorTests: XCTestCase {
    func testLargeCenteredMultilineTitleBeatsRotatedMarginText() {
        let lines = [
            line(
                "arXiv:2411.15287v1 [cs.CL] 22 Nov 2024",
                x: 0.028,
                y: 0.318,
                width: 0.033,
                height: 0.443
            ),
            line(
                "Sycophancy in Large Language Models: Causes",
                x: 0.235,
                y: 0.838,
                width: 0.535,
                height: 0.016
            ),
            line(
                "and Mitigations",
                x: 0.413,
                y: 0.815,
                width: 0.180,
                height: 0.016
            ),
            line("Lars Malmqvist", x: 0.447, y: 0.772, width: 0.112, height: 0.013),
            line(
                "Large language models have demonstrated remarkable capabilities across tasks",
                x: 0.266,
                y: 0.694,
                width: 0.473,
                height: 0.011
            ),
            line(
                "This paper provides a technical survey of sycophancy and mitigation strategies",
                x: 0.266,
                y: 0.625,
                width: 0.472,
                height: 0.011
            )
        ]

        XCTAssertEqual(
            VisualTitleDetector().title(in: lines),
            "Sycophancy in Large Language Models: Causes and Mitigations"
        )
    }

    func testUniformBodyTextDoesNotInventATitle() {
        let lines = (0..<8).map { index in
            line(
                "A regular paragraph line with no visual title hierarchy",
                x: 0.12,
                y: 0.8 - Double(index) * 0.04,
                width: 0.76,
                height: 0.018
            )
        }

        XCTAssertNil(VisualTitleDetector().title(in: lines))
    }

    func testGenericIdentifierIsNotPlausibleTitleMetadata() {
        XCTAssertFalse(
            VisualTitleDetector.isPlausibleTitleText(
                "arXiv:2411.15287v1 [cs.CL]"
            )
        )
        XCTAssertTrue(
            VisualTitleDetector.isPlausibleTitleText(
                "Sycophancy in Large Language Models"
            )
        )
    }

    private func line(
        _ text: String,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> RecognizedTextLine {
        RecognizedTextLine(
            text: text,
            confidence: 1,
            minX: x,
            minY: y,
            width: width,
            height: height
        )
    }
}
