import Foundation

/// One Vision text observation in normalized image coordinates.
///
/// Keeping this in SmartPerchCore lets the event log preserve OCR layout without
/// depending on Vision framework types.
public struct RecognizedTextLine: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Float
    public let minX: Double
    public let minY: Double
    public let width: Double
    public let height: Double

    public init(
        text: String,
        confidence: Float,
        minX: Double,
        minY: Double,
        width: Double,
        height: Double
    ) {
        self.text = text
        self.confidence = confidence
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }
    public var midX: Double { minX + width / 2 }
}

public struct ScreenshotNameSuggestion: Equatable, Sendable {
    public let displayName: String
    public let suggestedFilename: String

    public init(displayName: String, suggestedFilename: String) {
        self.displayName = displayName
        self.suggestedFilename = suggestedFilename
    }
}

/// Produces a human shelf label and an optional keepable filename from screenshot OCR.
///
/// Vision geometry lets large, central content win over tiny browser/app chrome.
/// Older flat OCR records still get a conservative fallback.
public struct ScreenshotFilenameSuggester: Sendable {
    public static let identifier = "screenshot-ocr-filename"
    public static let version = 5
    public static let maximumBaseNameLength = 48
    public static let maximumWordCount = 4

    public init() {}

    public func suggestName(
        from ocrText: String,
        recognizedLines: [RecognizedTextLine] = [],
        originalFilename: String
    ) -> ScreenshotNameSuggestion? {
        let originalExtension = URL(fileURLWithPath: originalFilename).pathExtension
        guard !originalExtension.isEmpty else { return nil }

        if let workspace = terminalWorkspaceContext(
            in: ocrText,
            recognizedLines: recognizedLines
        ) {
            return makeSuggestion(
                filenameWords: workspace.filenameWords,
                displayName: workspace.displayName,
                originalFilename: originalFilename,
                originalExtension: originalExtension
            )
        }

        let context = detectedContext(in: ocrText)
        if context == .messages {
            let titleWords = conversationTitle(
                in: recognizedLines
            )?.words
            let nameWords = titleWords ?? ["messages", "conversation"]
            let displayName = titleWords == nil
                ? "Messages conversation"
                : humanizedName(from: nameWords)
            return makeSuggestion(
                filenameWords: nameWords,
                displayName: displayName,
                originalFilename: originalFilename,
                originalExtension: originalExtension
            )
        }

        let candidates: [Candidate]
        if recognizedLines.isEmpty {
            candidates = ocrText
                .components(separatedBy: .newlines)
                .enumerated()
                .compactMap {
                    makeFallbackCandidate(lineNumber: $0.offset, line: $0.element)
                }
        } else {
            candidates = recognizedLines.enumerated().compactMap {
                makeLayoutCandidate(index: $0.offset, line: $0.element)
            }
        }

        let selectedWords: [String]
        if let best = candidates.max(by: { $0.score < $1.score }),
           recognizedLines.isEmpty || best.score >= 55 {
            selectedWords = wordsIncludingNearbySupport(
                for: best,
                among: candidates,
                maximumWords: context == nil ? Self.maximumWordCount : 3
            )
        } else if let context {
            selectedWords = [context.filenameWord, "screenshot"]
        } else {
            return nil
        }

        var filenameWords = selectedWords
        var displayName = humanizedName(from: selectedWords)
        if let context,
           !selectedWords.contains(context.filenameWord) {
            filenameWords.insert(context.filenameWord, at: 0)
            displayName = "\(context.displayName) · \(displayName)"
        } else if let context, selectedWords == [context.filenameWord, "screenshot"] {
            displayName = "\(context.displayName) screenshot"
        }

        return makeSuggestion(
            filenameWords: Array(filenameWords.prefix(Self.maximumWordCount)),
            displayName: displayName,
            originalFilename: originalFilename,
            originalExtension: originalExtension
        )
    }

    /// Compatibility convenience for callers that only need the filesystem name.
    public func suggestFilename(
        from ocrText: String,
        originalFilename: String
    ) -> String? {
        suggestName(
            from: ocrText,
            originalFilename: originalFilename
        )?.suggestedFilename
    }

    private func makeLayoutCandidate(
        index: Int,
        line: RecognizedTextLine
    ) -> Candidate? {
        let candidate = basicCandidate(
            lineNumber: index,
            line: line.text,
            layout: line
        )
        guard var candidate else { return nil }

        let clampedHeight = min(max(line.height, 0), 0.15)
        let centerAffinity = 1 - min(abs(line.midX - 0.5) * 2, 1)
        candidate.score += Int(clampedHeight * 1_400)
        candidate.score += Int(centerAffinity * 24)
        candidate.score += Int(max(0, min(line.confidence, 1)) * 16)

        // Browser/app navigation is usually both tiny and pressed against the top.
        if line.maxY > 0.91, line.height < 0.045 {
            candidate.score -= 120
        }
        if line.maxY < 0.08, line.height < 0.035 {
            candidate.score -= 30
        }
        return candidate
    }

    private func makeFallbackCandidate(
        lineNumber: Int,
        line: String
    ) -> Candidate? {
        guard var candidate = basicCandidate(
            lineNumber: lineNumber,
            line: line,
            layout: nil
        ) else {
            return nil
        }

        // Without geometry, top-to-bottom order is our only weak salience signal.
        candidate.score += 1_000 - min(lineNumber, 12) * 50
        return candidate
    }

    private func basicCandidate(
        lineNumber: Int,
        line: String,
        layout: RecognizedTextLine?
    ) -> Candidate? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikePathOrURL(trimmed) else {
            return nil
        }

        let rawWords = words(in: trimmed)
        let meaningfulWords = rawWords.filter(isMeaningful)
        guard !meaningfulWords.isEmpty else { return nil }

        let selectedWords = Array(meaningfulWords.prefix(Self.maximumWordCount))
        let alphabeticCharacterCount = selectedWords.reduce(into: 0) { count, word in
            count += word.unicodeScalars.filter {
                CharacterSet.letters.contains($0)
            }.count
        }
        guard alphabeticCharacterCount >= 3 else { return nil }

        let overflowPenalty = max(0, rawWords.count - Self.maximumWordCount) * 3
        let score = selectedWords.count * 8
            + min(alphabeticCharacterCount, 24)
            - overflowPenalty

        return Candidate(
            words: selectedWords,
            score: score,
            lineNumber: lineNumber,
            layout: layout
        )
    }

    /// Add one strongly related neighboring line, such as a channel below a video
    /// title. Horizontal overlap prevents unrelated columns/cards from being combined.
    private func wordsIncludingNearbySupport(
        for best: Candidate,
        among candidates: [Candidate],
        maximumWords: Int
    ) -> [String] {
        guard let bestLayout = best.layout,
              best.words.count < maximumWords
        else {
            return Array(best.words.prefix(maximumWords))
        }

        let support = candidates
            .filter { candidate in
                guard candidate.lineNumber != best.lineNumber,
                      let layout = candidate.layout,
                      candidate.score >= max(45, best.score / 2)
                else {
                    return false
                }

                let horizontalOverlap = max(
                    0,
                    min(bestLayout.maxX, layout.maxX)
                        - max(bestLayout.minX, layout.minX)
                )
                let overlapRatio = horizontalOverlap
                    / max(0.001, min(bestLayout.width, layout.width))
                let verticalGap = max(
                    0,
                    max(bestLayout.minY, layout.minY)
                        - min(bestLayout.maxY, layout.maxY)
                )
                return overlapRatio >= 0.5 && verticalGap <= 0.08
            }
            .max(by: { $0.score < $1.score })

        guard let support,
              best.words.count + support.words.count <= maximumWords
        else {
            return Array(best.words.prefix(maximumWords))
        }
        let ordered = [best, support].sorted {
            ($0.layout?.maxY ?? 0) > ($1.layout?.maxY ?? 0)
        }
        return Array(
            ordered.flatMap(\.words).prefix(maximumWords)
        )
    }

    private func detectedContext(in text: String) -> ScreenshotContext? {
        let allWords = Set(words(in: text))
        let lowercased = text.lowercased()

        if allWords.contains("imessage")
            || lowercased.contains("you reacted")
            || lowercased.contains("you loved") {
            return .messages
        }

        let videoMetricCount = actualVideoMetricCount(in: lowercased)
        let hasYouTubeChrome = allWords.contains("premium")
            || allWords.contains("shorts")
            || allWords.contains("subscribe")
            || allWords.contains("members")
        if (videoMetricCount >= 1 && hasYouTubeChrome)
            || (allWords.contains("youtube") && videoMetricCount >= 1)
            || videoMetricCount >= 2 {
            return .youtube
        }
        return nil
    }

    /// A mention of "views" in prose is not YouTube evidence. Real screenshots expose
    /// concrete metrics such as "17M views" or "240K subscribers".
    private func actualVideoMetricCount(in lowercasedText: String) -> Int {
        let pattern = #"\b\d+(?:\.\d+)?\s*[kmb]?\s+(?:views|subscribers?)\b"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else {
            return 0
        }
        return expression.numberOfMatches(
            in: lowercasedText,
            range: NSRange(
                lowercasedText.startIndex..<lowercasedText.endIndex,
                in: lowercasedText
            )
        )
    }

    /// Agent UIs, shells, build logs, and multiplexers all vary, but they share paths,
    /// prompts, commands, and command output. Classify that stable concept instead of
    /// guessing Codex or Claude from words that may merely occur in the transcript.
    private func terminalWorkspaceContext(
        in text: String,
        recognizedLines: [RecognizedTextLine]
    ) -> TerminalWorkspaceContext? {
        guard recognizedLines.count >= 8 else { return nil }

        let paths = terminalPaths(in: text)
        let promptCount = recognizedLines.count { looksLikeShellPrompt($0.text) }
        let commandCount = recognizedLines.count { containsLeadingShellCommand($0.text) }
        let outputCount = recognizedLines.count { containsTerminalOutput($0.text) }
        let structuralSignals = promptCount + commandCount + outputCount

        let hasPathBackedStructure =
            (paths.count >= 1 && structuralSignals >= 2)
            || (paths.count >= 2 && structuralSignals >= 1)
        let hasPromptBackedStructure = promptCount >= 1 && commandCount >= 1
        guard hasPathBackedStructure || hasPromptBackedStructure else {
            return nil
        }

        if let projectWords = projectWordsFromTerminalPaths(paths) {
            return TerminalWorkspaceContext(
                displayName: "Terminal · \(humanizedName(from: projectWords))",
                filenameWords: ["terminal"] + projectWords
            )
        }

        return TerminalWorkspaceContext(
            displayName: "Terminal workspace",
            filenameWords: ["terminal", "workspace"]
        )
    }

    private func terminalPaths(in text: String) -> [String] {
        let pattern =
            #"(?:(?:~)|(?:/Users/[^/\s]+)|(?:/Volumes/[^/\s]+))(?:/[A-Za-z0-9._+@-]+)+"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: []
        ) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func looksLikeShellPrompt(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["$", "%", "❯", "➜", "λ"].contains(where: trimmed.hasPrefix) {
            return true
        }
        return trimmed.contains(" λ ")
            || trimmed.contains(" ❯ ")
            || trimmed.contains(" ➜ ")
    }

    private func containsLeadingShellCommand(_ text: String) -> Bool {
        let leadingWords = words(in: text).prefix(6)
        return leadingWords.contains { Self.terminalCommandWords.contains($0) }
    }

    private func containsTerminalOutput(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return Self.terminalOutputPhrases.contains {
            lowercased.contains($0)
        }
    }

    /// Prefer project names repeated in working-directory and build paths. Generic
    /// containers such as `Projects`, `Swift`, and `Sources` are ignored.
    private func projectWordsFromTerminalPaths(
        _ paths: [String]
    ) -> [String]? {
        var scores: [String: (words: [String], score: Int)] = [:]

        for path in paths {
            var components = path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            if components.first == "~" {
                components.removeFirst()
            } else if components.first?.lowercased() == "users",
                      components.count >= 2 {
                components.removeFirst(2)
            } else if components.first?.lowercased() == "volumes",
                      components.count >= 2 {
                components.removeFirst(2)
            }

            for (index, component) in components.enumerated() {
                let pathExtension = (component as NSString).pathExtension.lowercased()
                let isApplication = pathExtension == "app"
                if !pathExtension.isEmpty && !isApplication {
                    break
                }

                let candidateBase = isApplication
                    ? (component as NSString).deletingPathExtension
                    : component
                let candidateWords = words(in: candidateBase).filter {
                    isMeaningful($0)
                        && !Self.genericTerminalPathWords.contains($0)
                        && !$0.unicodeScalars.allSatisfy {
                            CharacterSet.decimalDigits.contains($0)
                        }
                }
                guard !candidateWords.isEmpty,
                      candidateWords.count <= 2,
                      !candidateBase.hasPrefix("."),
                      !looksLikeUUID(candidateBase)
                else { continue }

                var score = 1
                let isLastComponent = index == components.index(before: components.endIndex)
                if isLastComponent || isApplication {
                    score += 4
                } else if index + 1 < components.count {
                    let nextWords = Set(words(in: components[index + 1]))
                    if !nextWords.isDisjoint(with: Self.projectChildPathWords) {
                        score += 3
                    }
                }

                let key = candidateWords.joined(separator: "-")
                let existing = scores[key]
                scores[key] = (
                    words: candidateWords,
                    score: (existing?.score ?? 0) + score
                )

                if isApplication {
                    break
                }
            }
        }

        return scores.sorted { first, second in
            if first.value.score != second.value.score {
                return first.value.score > second.value.score
            }
            if first.value.words.count != second.value.words.count {
                return first.value.words.count < second.value.words.count
            }
            return first.key < second.key
        }.first?.value.words
    }

    private func looksLikeUUID(_ value: String) -> Bool {
        let compact = value.replacingOccurrences(of: "-", with: "")
        guard compact.count == 32 else { return false }
        let hexadecimalDigits = CharacterSet(
            charactersIn: "0123456789abcdefABCDEF"
        )
        return compact.unicodeScalars.allSatisfy {
            hexadecimalDigits.contains($0)
        }
    }

    /// Messages puts the conversation title in a compact centered line above the
    /// transcript. If that title is cropped away, return nil so we use an honest
    /// generic label instead of naming the screenshot after somebody's message.
    private func conversationTitle(
        in recognizedLines: [RecognizedTextLine]
    ) -> Candidate? {
        recognizedLines.enumerated()
            .compactMap { index, line -> Candidate? in
                guard line.minY >= 0.76,
                      line.midX >= 0.42,
                      line.midX <= 0.72
                else {
                    return nil
                }
                let meaningfulWords = words(in: line.text).filter(isMeaningful)
                guard !meaningfulWords.isEmpty,
                      meaningfulWords.count <= Self.maximumWordCount
                else {
                    return nil
                }
                return basicCandidate(
                    lineNumber: index,
                    line: line.text,
                    layout: line
                )
            }
            .max {
                let firstY = $0.layout?.maxY ?? 0
                let secondY = $1.layout?.maxY ?? 0
                return firstY < secondY
            }
    }

    private func words(in text: String) -> [String] {
        text
            .folding(
                options: [.diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
    }

    private func isMeaningful(_ word: String) -> Bool {
        guard !Self.stopWords.contains(word) else { return false }

        let isNumeric = word.unicodeScalars.allSatisfy {
            CharacterSet.decimalDigits.contains($0)
        }
        if isNumeric {
            return word.count >= 3
        }
        return word.count >= 2
    }

    private func looksLikePathOrURL(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        if lowercased.contains("://")
            || lowercased.hasPrefix("www.")
            || lowercased.contains("/users/")
            || lowercased.contains("/library/")
            || lowercased.contains("\\users\\") {
            return true
        }

        let slashCount = line.reduce(into: 0) { count, character in
            if character == "/" || character == "\\" {
                count += 1
            }
        }
        return slashCount >= 3
    }

    private func limitedBaseName(from words: [String]) -> String {
        var accepted: [String] = []
        var length = 0

        for word in words {
            let addedLength = word.count + (accepted.isEmpty ? 0 : 1)
            guard length + addedLength <= Self.maximumBaseNameLength else {
                break
            }
            accepted.append(word)
            length += addedLength
        }

        return accepted.joined(separator: "-")
    }

    private func normalizedBaseName(_ name: String) -> String {
        limitedBaseName(from: words(in: name).filter(isMeaningful))
    }

    private func makeSuggestion(
        filenameWords: [String],
        displayName: String,
        originalFilename: String,
        originalExtension: String
    ) -> ScreenshotNameSuggestion? {
        let baseName = limitedBaseName(
            from: Array(filenameWords.prefix(Self.maximumWordCount))
        )
        guard !baseName.isEmpty else { return nil }

        let originalBaseName = URL(fileURLWithPath: originalFilename)
            .deletingPathExtension()
            .lastPathComponent
        guard normalizedBaseName(originalBaseName) != baseName else {
            return nil
        }

        return ScreenshotNameSuggestion(
            displayName: displayName,
            suggestedFilename: "\(baseName).\(originalExtension)"
        )
    }

    private func humanizedName(from words: [String]) -> String {
        words.map {
            Self.brandCapitalization[$0] ?? $0.capitalized
        }.joined(separator: " ")
    }

    private struct Candidate {
        let words: [String]
        var score: Int
        let lineNumber: Int
        let layout: RecognizedTextLine?
    }

    private struct TerminalWorkspaceContext {
        let displayName: String
        let filenameWords: [String]
    }

    private enum ScreenshotContext: Equatable {
        case youtube
        case messages

        var displayName: String {
            switch self {
            case .youtube: return "YouTube"
            case .messages: return "Messages"
            }
        }

        var filenameWord: String {
            switch self {
            case .youtube: return "youtube"
            case .messages: return "messages"
            }
        }
    }

    private static let brandCapitalization: [String: String] = [
        "codex": "Codex",
        "github": "GitHub",
        "ios": "iOS",
        "macos": "macOS",
        "ocr": "OCR",
        "pdf": "PDF",
        "swiftui": "SwiftUI",
        "terminal": "Terminal",
        "xcode": "Xcode",
        "youtube": "YouTube"
    ]

    private static let terminalCommandWords: Set<String> = [
        "brew", "cargo", "cd", "chmod", "code", "cp", "curl", "docker", "find",
        "git", "gradle", "grep", "kill", "ls", "make", "mkdir", "mv", "npm",
        "npx", "open", "pnpm", "python", "python3", "rg", "ruby", "swift",
        "swiftc", "tail", "xcodebuild", "yarn"
    ]

    private static let terminalOutputPhrases = [
        "build complete",
        "building for ",
        "committed ",
        "compiling ",
        "crunched for ",
        "error:",
        "executed ",
        "exit code ",
        "installing to ",
        "linking ",
        "process exited",
        "ran ",
        "test suite ",
        "tests pass",
        "warning:",
        "worked for "
    ]

    private static let genericTerminalPathWords: Set<String> = [
        "application", "applications", "build", "code", "coding", "contents",
        "current", "debug", "dev", "developer", "development", "files",
        "frameworks", "go", "home", "items", "java", "javascript", "kotlin",
        "library", "node", "packages", "private", "project", "projects", "python",
        "release", "repos", "repositories", "rust", "scripts", "source", "sources",
        "support", "swift", "tests", "typescript", "users", "versions", "workspace",
        "workspaces", "xpcservices"
    ]

    private static let projectChildPathWords: Set<String> = [
        "app", "build", "contents", "package", "packages", "scripts", "source",
        "sources", "tests"
    ]

    private static let stopWords: Set<String> = [
        "a", "about", "all", "an", "and", "are", "as", "at", "back", "be", "been",
        "but", "by", "cancel", "click", "close", "copy", "delete", "done", "edit",
        "file", "for", "from", "go", "has", "have", "help", "history", "home", "in",
        "is", "it", "its", "library", "more", "new", "next", "no", "not", "of", "ok",
        "on", "open", "or", "premium", "save", "search", "select", "share", "shorts",
        "show", "subscribe", "subscriber", "subscribers", "that", "the", "this", "to",
        "view", "views", "was", "were", "will", "window", "with", "yes", "you",
        "youtube", "your"
    ]
}
