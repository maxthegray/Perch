import XCTest
@testable import SmartPerchCore

final class ScreenshotFilenameSuggesterTests: XCTestCase {
    private let suggester = ScreenshotFilenameSuggester()

    func testUsesShortMeaningfulHeadingAndPreservesExtension() {
        let suggestion = suggester.suggestFilename(
            from: """
                Invoice 4821
                Amount due 150 dollars
                """,
            originalFilename: "Screenshot 2026-07-26 at 1.39.00 AM.PNG"
        )

        XCTAssertEqual(suggestion, "invoice-4821.PNG")
    }

    func testIgnoresInterfaceChromeAndPathNoise() {
        let suggestion = suggester.suggestFilename(
            from: """
                File Edit View Window Help
                /Users/max/Library/Application Support/Perch/items/file.png
                Smart Perch release notes
                """,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(suggestion, "smart-perch-release-notes.png")
    }

    func testProducesFilesystemSafeBoundedName() {
        let suggestion = suggester.suggestFilename(
            from: "Quarterly Revenue: North / America? Forecast * Final Version Approved",
            originalFilename: "Screenshot.jpeg"
        )

        XCTAssertEqual(
            suggestion,
            "quarterly-revenue-north-america.jpeg"
        )
        XCTAssertLessThanOrEqual(
            suggestion?.deletingPathExtension.count ?? .max,
            ScreenshotFilenameSuggester.maximumBaseNameLength
        )
    }

    func testReturnsNilForNoiseOrEquivalentExistingName() {
        XCTAssertNil(
            suggester.suggestFilename(
                from: "File Edit View Window",
                originalFilename: "Screenshot.png"
            )
        )
        XCTAssertNil(
            suggester.suggestFilename(
                from: "Smart Perch",
                originalFilename: "smart-perch.png"
            )
        )
    }

    func testLayoutIgnoresYouTubeChromeAndCombinesNearbyTitleContext() {
        let suggestion = suggester.suggestName(
            from: """
                YouTube
                Premium
                The Disturbing Case
                Dr Insanity
                1.2M views
                """,
            recognizedLines: [
                line("Premium", x: 0.05, y: 0.94, width: 0.12, height: 0.02),
                line("The Disturbing Case", x: 0.18, y: 0.56, width: 0.48, height: 0.065),
                line("Dr Insanity", x: 0.18, y: 0.50, width: 0.19, height: 0.025),
                line("1.2M views", x: 0.18, y: 0.46, width: 0.15, height: 0.018)
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "YouTube · Disturbing Case",
                suggestedFilename: "youtube-disturbing-case.png"
            )
        )
    }

    func testMessagesScreenshotUsesConversationTitleNotMessageBody() {
        let suggestion = suggester.suggestName(
            from: """
                Lachlan Wession
                Search
                Like look at the mermaids pendant one
                But then im leaving for houston so idk
                You reacted
                iMessage
                """,
            recognizedLines: [
                line("Lachlan Wession", x: 0.45, y: 0.80, width: 0.12, height: 0.014),
                line(
                    "Like look at the mermaids pendant one",
                    x: 0.37,
                    y: 0.77,
                    width: 0.28,
                    height: 0.016
                ),
                line(
                    "But then im leaving for houston so idk",
                    x: 0.37,
                    y: 0.39,
                    width: 0.30,
                    height: 0.016
                ),
                line("iMessage", x: 0.37, y: 0.32, width: 0.08, height: 0.014)
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Lachlan Wession",
                suggestedFilename: "lachlan-wession.png"
            )
        )
    }

    func testMessagesScreenshotWithoutVisibleTitleUsesGenericLabel() {
        let suggestion = suggester.suggestName(
            from: "Message contents here\nYou loved a message\niMessage",
            recognizedLines: [
                line(
                    "Message contents here",
                    x: 0.30,
                    y: 0.55,
                    width: 0.30,
                    height: 0.02
                ),
                line("iMessage", x: 0.35, y: 0.08, width: 0.10, height: 0.015)
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Messages conversation",
                suggestedFilename: "messages-conversation.png"
            )
        )
    }

    func testIncidentalYouTubeShelfLabelDoesNotClassifyUnrelatedScreenshot() {
        let suggestion = suggester.suggestName(
            from: "GitHub Contributions\nCommits over time\nYouTube Contributions",
            recognizedLines: [
                line(
                    "GitHub Contributions",
                    x: 0.25,
                    y: 0.55,
                    width: 0.35,
                    height: 0.05
                ),
                line(
                    "YouTube Contributions",
                    x: 0.10,
                    y: 0.10,
                    width: 0.20,
                    height: 0.02
                )
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "GitHub Contributions",
                suggestedFilename: "github-contributions.png"
            )
        )
    }

    func testLowInformationYouTubeScreenshotGetsHonestGenericLabel() {
        let suggestion = suggester.suggestName(
            from: "Premium\n1.2M views",
            recognizedLines: [
                line("Premium", x: 0.05, y: 0.94, width: 0.12, height: 0.02),
                line("1.2M views", x: 0.20, y: 0.40, width: 0.15, height: 0.018)
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "YouTube screenshot",
                suggestedFilename: "youtube-screenshot.png"
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
            confidence: 0.9,
            minX: x,
            minY: y,
            width: width,
            height: height
        )
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
