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

    func testYouTubeDiscussionDoesNotCountAsYouTubeInterface() {
        let suggestion = suggester.suggestName(
            from: """
                OCR Classification Notes
                YouTube detection requires views or subscribers
                Premium Shorts Subscribe Members
                """,
            recognizedLines: [
                line(
                    "OCR Classification Notes",
                    x: 0.24,
                    y: 0.58,
                    width: 0.40,
                    height: 0.055
                ),
                line(
                    "YouTube detection requires views or subscribers",
                    x: 0.20,
                    y: 0.48,
                    width: 0.55,
                    height: 0.025
                ),
                line(
                    "Premium Shorts Subscribe Members",
                    x: 0.20,
                    y: 0.43,
                    width: 0.42,
                    height: 0.025
                )
            ],
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "OCR Classification Notes",
                suggestedFilename: "ocr-classification-notes.png"
            )
        )
    }

    func testGmailLoadingScreenUsesAnchoredAppIdentity() {
        let lines = [
            line("Gmail", x: 0.074, y: 0.959, width: 0.045, height: 0.019),
            line(
                "has:attachments",
                x: 0.201,
                y: 0.961,
                width: 0.14,
                height: 0.019
            ),
            line("Active", x: 0.79, y: 0.948, width: 0.08, height: 0.049),
            line("Compose", x: 0.073, y: 0.894, width: 0.08, height: 0.017),
            line("Mail", x: 0.007, y: 0.875, width: 0.04, height: 0.014),
            line("Inbox", x: 0.073, y: 0.836, width: 0.05, height: 0.015),
            line("Starred", x: 0.074, y: 0.805, width: 0.07, height: 0.014),
            line("Snoozed", x: 0.074, y: 0.774, width: 0.08, height: 0.015),
            line("Sent", x: 0.074, y: 0.743, width: 0.04, height: 0.012),
            line("Labels", x: 0.051, y: 0.625, width: 0.06, height: 0.014)
        ]

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Gmail",
                suggestedFilename: "gmail.png"
            )
        )
    }

    func testGmailMentionInDocumentDoesNotImpersonateAppChrome() {
        let lines = [
            line(
                "Gmail Productivity Guide",
                x: 0.24,
                y: 0.62,
                width: 0.43,
                height: 0.055
            ),
            line(
                "Organize newsletters and receipts",
                x: 0.20,
                y: 0.50,
                width: 0.50,
                height: 0.022
            ),
            line(
                "Create filters for recurring mail",
                x: 0.20,
                y: 0.44,
                width: 0.48,
                height: 0.022
            )
        ]

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Gmail Productivity Guide",
                suggestedFilename: "gmail-productivity-guide.png"
            )
        )
    }

    func testDenseTerminalWorkspaceUsesProjectPathInsteadOfBodyText() {
        let topLines = [
            line("Perch", x: 0.029, y: 0.966, width: 0.029, height: 0.011),
            line(
                "codex-aarch64-a",
                x: 0.071,
                y: 0.964,
                width: 0.081,
                height: 0.014
            ),
            line("beta", x: 0.648, y: 0.963, width: 0.034, height: 0.017),
            line(
                "gpt-5.6-sol xhigh",
                x: 0.695,
                y: 0.961,
                width: 0.093,
                height: 0.018
            )
        ]
        let bodyTexts = [
            "Smart Names are capped at four words",
            "How does it know if something is YouTube",
            "views or subscribers plus Premium Shorts",
            "auto mode on",
            "Worked for 5m 44s",
            "Building for production",
            "Perch marks something as YouTube",
            "Subscribe or Members",
            "Changes remain uncommitted on beta",
            "~/Coding/Swift/Perch λ swift test"
        ]
        let bodyLines = bodyTexts.enumerated().map { index, text in
            line(
                text,
                x: index.isMultiple(of: 2) ? 0.02 : 0.51,
                y: 0.90 - Double(index) * 0.06,
                width: 0.42,
                height: 0.016
            )
        }
        let lines = topLines + bodyLines

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Terminal · Perch",
                suggestedFilename: "terminal-perch.png"
            )
        )
    }

    func testClaudeTerminalDoesNotBecomeCodexFromTranscriptText() {
        let texts = [
            "claude",
            "Opus 4.8 high",
            "Committed in ~/dotfiles, no Claude tag",
            "Tracked .codex/statusline.py",
            "Codex still reads it",
            "Left untracked on purpose: ~/.codex/config.toml",
            "Ran git status --short --branch",
            "Crunched for 3m 32s",
            "auto mode on",
            "UserPromptSubmit PostToolUse SessionEnd",
            "Changes remain in .claude/settings.json",
            "Not pushed yet"
        ]
        let lines = texts.enumerated().map { index, text in
            line(
                text,
                x: index.isMultiple(of: 2) ? 0.02 : 0.51,
                y: 0.97 - Double(index) * 0.07,
                width: 0.46,
                height: 0.017
            )
        }

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Terminal · Dotfiles",
                suggestedFilename: "terminal-dotfiles.png"
            )
        )
    }

    func testMixedAgentTerminalUsesRepeatedProjectPathNotToolNames() {
        let texts = [
            "claude",
            "Opus 4.8 high",
            "gpt-5.6-sol xhigh",
            "Auto-reviewer approved codex to run ./Scripts/build-app.sh",
            "Ran git status --short --branch",
            "Building for production",
            "Build complete",
            "~/Coding/Swift/Perch λ ./Scripts/install.sh",
            "/Users/person/Coding/Swift/Perch/Perch.app/Contents/MacOS/Perch",
            "Codex and Claude discussion",
            "Terminal output",
            "Tests pass"
        ]
        let lines = texts.enumerated().map { index, text in
            line(
                text,
                x: index.isMultiple(of: 2) ? 0.01 : 0.50,
                y: 0.97 - Double(index) * 0.07,
                width: 0.48,
                height: 0.016
            )
        }

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Terminal · Perch",
                suggestedFilename: "terminal-perch.png"
            )
        )
    }

    func testArticleMentioningACommandAndPathIsNotATerminalWorkspace() {
        let texts = [
            "A Practical Terminal Guide",
            "This article explains repository health",
            "Run git status before committing",
            "The example lives at ~/Projects/sample",
            "Choose a branch naming convention",
            "Review every change carefully",
            "Share the result with your team",
            "Automate only repetitive work",
            "Keep local configuration private",
            "Document the expected workflow",
            "Prefer small focused commits",
            "Summary and next steps"
        ]
        let lines = texts.enumerated().map { index, text in
            line(
                text,
                x: index == 0 ? 0.24 : 0.18,
                y: 0.80 - Double(index) * 0.055,
                width: index == 0 ? 0.42 : 0.62,
                height: index == 0 ? 0.055 : 0.018
            )
        }

        let suggestion = suggester.suggestName(
            from: lines.map(\.text).joined(separator: "\n"),
            recognizedLines: lines,
            originalFilename: "Screenshot.png"
        )

        XCTAssertEqual(
            suggestion,
            ScreenshotNameSuggestion(
                displayName: "Practical Terminal Guide",
                suggestedFilename: "practical-terminal-guide.png"
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
