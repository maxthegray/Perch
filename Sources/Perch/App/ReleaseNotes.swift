import Foundation

/// One line of "here is what changed", in the same shape as a welcome-window lesson so
/// the two windows can share a row view and stay visually identical.
struct ReleaseHighlight: Decodable, Equatable {
    let symbol: String
    let title: String
    let detail: String
}

/// Everything worth saying about one released version.
struct ReleaseNote: Decodable, Equatable {
    let version: SemanticVersion
    /// One line under the title. Optional: a maintenance release rarely earns one.
    let headline: String?
    let highlights: [ReleaseHighlight]
    /// When true, users updating *into* this version are shown the welcome window again
    /// instead of these notes. For a release that changes how Perch introduces itself,
    /// where showing the thing beats describing it. Rare by design — it interrupts people
    /// who already know the app, so it has to earn the interruption.
    let showsWelcome: Bool?

    var revisitsWelcome: Bool { showsWelcome == true }
}

/// A `MAJOR.MINOR.PATCH` version that can be ordered, so "everything since the version
/// you last saw" is a comparison rather than string matching.
struct SemanticVersion: Comparable, Hashable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `1.2.3`. Anything else — a build tag, an empty string, the "Development"
    /// placeholder an unbundled binary reports — is not a version and is refused, because
    /// guessing one would silently show or hide the wrong notes.
    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

extension SemanticVersion: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = SemanticVersion(raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(raw) is not a MAJOR.MINOR.PATCH version"
            )
        }
        self = parsed
    }
}

/// Loads the bundled release notes.
///
/// The notes live in `Resources/ReleaseNotes.json` rather than in Swift so that
/// `Scripts/release.sh` can read the same file and publish the same words to the appcast
/// and the GitHub release — one place to write them, three places they appear.
enum ReleaseNotes {
    private struct Document: Decodable {
        let versions: [ReleaseNote]
    }

    static let resourceName = "ReleaseNotes"

    /// Every note in the bundle, newest first. Missing or malformed notes are not an
    /// error worth interrupting a launch for: the What's New window simply has nothing to
    /// say, which is exactly how an unbundled `swift run` build should behave.
    static func bundled(in bundle: Bundle = .main) -> [ReleaseNote] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            return []
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            NSLog("Perch could not read \(resourceName).json: \(error)")
            return []
        }
    }

    static func decode(_ data: Data) throws -> [ReleaseNote] {
        try JSONDecoder()
            .decode(Document.self, from: data)
            .versions
            .sorted { $0.version > $1.version }
    }
}
