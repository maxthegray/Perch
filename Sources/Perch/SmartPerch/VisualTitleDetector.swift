import Foundation
import SmartPerchCore

struct VisualTitleDetector: Sendable {
    private struct Candidate {
        let line: RecognizedTextLine
        let score: Double
        let relativeHeight: Double
    }

    func title(in sourceLines: [RecognizedTextLine]) -> String? {
        let lines = sourceLines.compactMap(Self.normalizedLine)
            .filter(Self.hasUsableGeometry)
        guard !lines.isEmpty else { return nil }

        let medianHeight = Self.median(lines.map(\.height))
        let candidates = lines.compactMap { line in
            makeCandidate(
                from: line,
                medianHeight: medianHeight,
                lineCount: lines.count
            )
        }
        guard let best = candidates.max(by: { $0.score < $1.score }),
              best.score >= 55,
              lines.count < 4 || best.relativeHeight >= 1.15 else {
            return nil
        }

        let titleLines = neighboringTitleLines(around: best.line, in: lines)
        let title = titleLines
            .sorted { $0.maxY > $1.maxY }
            .map(\.text)
            .joined(separator: " ")
        return Self.isPlausibleTitleText(title) ? title : nil
    }

    static func isPlausibleTitleText(_ text: String) -> Bool {
        let normalized = normalizedText(text)
        let words = normalized.split(whereSeparator: { $0.isWhitespace })
        guard words.count <= 18,
              normalized.count <= 180 else {
            return false
        }

        let scalars = normalized.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        guard letterCount >= 3,
              digitCount <= max(4, Int(Double(letterCount) * 0.65)) else {
            return false
        }

        let punctuationCount = scalars.count - letterCount - digitCount
        return punctuationCount <= max(8, letterCount / 2)
    }

    private func makeCandidate(
        from line: RecognizedTextLine,
        medianHeight: Double,
        lineCount: Int
    ) -> Candidate? {
        let text = Self.normalizedText(line.text)
        guard Self.isPlausibleTitleText(text) else { return nil }

        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        let relativeHeight = line.height / max(0.001, medianHeight)
        let centerAffinity = 1 - min(abs(line.midX - 0.5) * 2, 1)
        let verticalCenter = line.minY + line.height / 2
        let upperPageAffinity = max(0, 1 - abs(verticalCenter - 0.73) / 0.55)
        let characterDensity = Double(text.count) / max(0.05, line.width)

        var score = min(relativeHeight, 5) * 24
        score += min(line.height, 0.1) * 60
        score += centerAffinity * 16
        score += upperPageAffinity * 12
        score += min(Double(wordCount), 6) * 1.5
        score += min(line.width / max(line.height, 0.001), 12) * 0.5
        score -= max(0, Double(wordCount - 12)) * 4
        score -= max(0, characterDensity - 150) * 0.08

        if line.maxY < 0.2 { score -= 25 }
        if line.maxY > 0.97, relativeHeight < 1.5 { score -= 20 }
        if line.midX < 0.1 || line.midX > 0.9 { score -= 30 }
        if lineCount >= 4, relativeHeight < 1.2 { score -= 20 }

        return Candidate(
            line: line,
            score: score,
            relativeHeight: relativeHeight
        )
    }

    private func neighboringTitleLines(
        around seed: RecognizedTextLine,
        in lines: [RecognizedTextLine]
    ) -> [RecognizedTextLine] {
        var selected = [seed]
        for _ in 0..<2 {
            let neighbors = lines.filter { candidateLine in
                guard !selected.contains(where: { $0 == candidateLine }),
                      Self.isPlausibleTitleText(candidateLine.text) else {
                    return false
                }
                let heightRatio = min(candidateLine.height, seed.height)
                    / max(candidateLine.height, seed.height)
                guard heightRatio >= 0.72,
                      abs(candidateLine.midX - seed.midX) <= 0.2 else {
                    return false
                }
                return selected.contains { existing in
                    Self.verticalGap(between: candidateLine, and: existing)
                        <= max(candidateLine.height, existing.height) * 1.15
                }
            }
            guard let neighbor = neighbors.min(by: {
                    Self.verticalGap(between: $0, and: seed)
                        < Self.verticalGap(between: $1, and: seed)
            }) else {
                break
            }
            selected.append(neighbor)
        }
        return selected
    }

    private static func normalizedLine(
        _ line: RecognizedTextLine
    ) -> RecognizedTextLine? {
        let text = normalizedText(line.text)
        guard !text.isEmpty else { return nil }
        return RecognizedTextLine(
            text: text,
            confidence: line.confidence,
            minX: line.minX,
            minY: line.minY,
            width: line.width,
            height: line.height
        )
    }

    private static func hasUsableGeometry(_ line: RecognizedTextLine) -> Bool {
        line.width >= 0.025
            && line.height >= 0.004
            && line.height <= 0.25
            && line.width >= line.height * 1.2
            && line.minX < 1
            && line.minY < 1
            && line.maxX > 0
            && line.maxY > 0
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func verticalGap(
        between first: RecognizedTextLine,
        and second: RecognizedTextLine
    ) -> Double {
        max(0, max(first.minY, second.minY) - min(first.maxY, second.maxY))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
