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
/// Version 2 uses Vision geometry when available: large, central content wins over
/// tiny browser/app chrome. Older flat OCR records still get a conservative fallback.
public struct ScreenshotFilenameSuggester: Sendable {
    public static let identifier = "screenshot-ocr-filename"
    public static let version = 3
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

        let hasVideoMetrics = allWords.contains("views")
            || allWords.contains("subscribers")
        let hasYouTubeChrome = allWords.contains("premium")
            || allWords.contains("shorts")
            || allWords.contains("subscribe")
            || allWords.contains("members")
        if (hasVideoMetrics && hasYouTubeChrome)
            || (allWords.contains("youtube") && hasVideoMetrics) {
            return .youtube
        }
        return nil
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
        "github": "GitHub",
        "ios": "iOS",
        "macos": "macOS",
        "pdf": "PDF",
        "swiftui": "SwiftUI",
        "xcode": "Xcode",
        "youtube": "YouTube"
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
