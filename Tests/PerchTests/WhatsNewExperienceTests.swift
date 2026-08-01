import Foundation
import XCTest
@testable import Perch

final class WhatsNewExperienceTests: XCTestCase {
    // MARK: - Ordering versions

    func testVersionsCompareByNumberNotByText() {
        // The string comparison every version scheme gets wrong exactly once.
        XCTAssertTrue(SemanticVersion("1.10.0")! > SemanticVersion("1.9.0")!)
        XCTAssertTrue(SemanticVersion("2.0.0")! > SemanticVersion("1.99.99")!)
        XCTAssertEqual(SemanticVersion("1.0.0"), SemanticVersion("1.0.0"))
    }

    func testSomethingThatIsNotAVersionIsRefused() {
        // An unbundled build reports "Development"; guessing a version from it would show
        // or hide notes at random.
        XCTAssertNil(SemanticVersion("Development"))
        XCTAssertNil(SemanticVersion("1.0"))
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("1.0.0-beta"))
    }

    // MARK: - Deciding what to show

    func testAnUpdateShowsTheNotesForTheVersionItLandedOn() {
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [note("1.1.0", announces: true), note("1.0.0")]
        )
        XCTAssertEqual(decision, .show([note("1.1.0", announces: true)]))
    }

    func testSkippingReleasesShowsEverythingThatWasMissed() {
        // Someone who updates once a month should still learn what arrived in between.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.3.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [note("1.3.0", announces: true), note("1.2.0", announces: true),
                    note("1.1.0", announces: true), note("1.0.0")]
        )
        XCTAssertEqual(decision, .show([note("1.3.0", announces: true),
                                       note("1.2.0", announces: true),
                                       note("1.1.0", announces: true)]))
    }

    func testNotesNewerThanTheRunningVersionAreNotLeaked() {
        // The bundle can legitimately carry an entry for a version this build is not, if
        // notes are written before the release is cut.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [note("1.2.0", announces: true), note("1.1.0", announces: true)]
        )
        XCTAssertEqual(decision, .show([note("1.1.0", announces: true)]))
    }

    func testRelaunchingTheSameVersionSaysNothing() {
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: SemanticVersion("1.1.0")!,
            notes: [note("1.1.0", announces: true)]
        )
        XCTAssertEqual(decision, .none)
    }

    func testDowngradingSaysNothing() {
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.0.0")!,
            lastSeenVersion: SemanticVersion("1.1.0")!,
            notes: [note("1.1.0", announces: true), note("1.0.0")]
        )
        XCTAssertEqual(decision, .none)
    }

    func testAnInstallThatPredatesTheWindowHearsOnlyAboutTheVersionItIsOn() {
        // No stamp means no way to know what it has already seen. Showing the whole
        // history to a long-time user would be a wall of things they lived through.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: nil,
            notes: [note("1.1.0", announces: true), note("1.0.0")]
        )
        XCTAssertEqual(decision, .show([note("1.1.0", announces: true)]))
    }

    func testAReleaseWithNoNotesShowsNothing() {
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [note("1.0.0")]
        )
        XCTAssertEqual(decision, .none)
    }

    // MARK: - Staying quiet

    func testAnOrdinaryReleaseOpensNoWindowAtAll() {
        // The default. A fix does not earn an interruption; its notes still ship in the
        // appcast and on the release page for anyone who goes looking.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.1")!,
            lastSeenVersion: SemanticVersion("1.1.0")!,
            notes: [note("1.1.1"), note("1.1.0")]
        )
        XCTAssertEqual(decision, .none)
    }

    func testCatchingUpSkipsTheQuietReleasesAndKeepsTheNotableOne() {
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.3.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [note("1.3.0"), note("1.2.0", announces: true), note("1.1.0")]
        )
        XCTAssertEqual(decision, .show([note("1.2.0", announces: true)]))
    }

    func testAFreshStampedInstallOnAQuietReleaseSaysNothing() {
        // No last-seen stamp and the version it landed on is an ordinary release.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.1")!,
            lastSeenVersion: nil,
            notes: [note("1.1.1"), note("1.1.0", announces: true)]
        )
        XCTAssertEqual(decision, .none)
    }

    func testRevisitingTheWelcomeCountsAsAnnouncingItself() {
        // A release loud enough to redo the tour cannot also be a silent one.
        let decision = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("2.0.0")!,
            lastSeenVersion: SemanticVersion("1.1.0")!,
            notes: [note("2.0.0", showsWelcome: true)]
        )
        XCTAssertEqual(decision, .show([note("2.0.0", showsWelcome: true)]))
    }

    // MARK: - Showing the tour again

    func testAReleaseCanAskToShowTheWelcomeInsteadOfItsNotes() {
        let tour = note("1.1.0", showsWelcome: true)
        guard case let .show(notes) = WhatsNewExperience.decide(
            currentVersion: SemanticVersion("1.1.0")!,
            lastSeenVersion: SemanticVersion("1.0.0")!,
            notes: [tour]
        ) else {
            return XCTFail("expected the 1.1.0 notes")
        }
        XCTAssertTrue(notes.contains(where: \.revisitsWelcome))
    }

    func testAnOrdinaryReleaseDoesNotReopenTheWelcome() {
        XCTAssertFalse(note("1.1.0").revisitsWelcome)
    }

    // MARK: - The bundled file

    func testTheShippedNotesParseAndAreOrderedNewestFirst() {
        // Guards the file every release edits by hand.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PerchTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Resources/ReleaseNotes.json")
        let data = try? Data(contentsOf: url)
        XCTAssertNotNil(data, "Resources/ReleaseNotes.json should exist")
        guard let data else { return }

        let notes = try? ReleaseNotes.decode(data)
        XCTAssertNotNil(notes, "Resources/ReleaseNotes.json should decode")
        guard let notes else { return }

        XCTAssertFalse(notes.isEmpty)
        XCTAssertEqual(notes, notes.sorted { $0.version > $1.version })
        for note in notes {
            XCTAssertFalse(
                note.highlights.isEmpty,
                "\(note.version) should say at least one thing"
            )
        }
    }

    private func note(
        _ version: String,
        showsWelcome: Bool? = nil,
        announces: Bool? = nil
    ) -> ReleaseNote {
        ReleaseNote(
            version: SemanticVersion(version)!,
            headline: nil,
            highlights: [
                ReleaseHighlight(symbol: "star", title: "Something", detail: "Happened.")
            ],
            showsWelcome: showsWelcome,
            showsWhatsNew: announces
        )
    }
}
