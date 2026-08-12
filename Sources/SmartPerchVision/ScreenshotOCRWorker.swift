import CoreGraphics
import Foundation
import ImageIO
import SmartPerchCore
import Vision

public struct ScreenshotOCRResult: Equatable, Sendable {
    public let text: String?
    public let lines: [RecognizedTextLine]
    public let durationMilliseconds: Int64

    public init(
        text: String?,
        lines: [RecognizedTextLine],
        durationMilliseconds: Int64
    ) {
        self.text = text
        self.lines = lines
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum ScreenshotOCRError: Error {
    case unreadableImage
    case thumbnailCreationFailed
}

/// A dedicated serial utility queue keeps Vision and image decoding away from both
/// the main actor and Swift's cooperative task pool.
public final class ScreenshotOCRWorker: @unchecked Sendable {
    public static let maximumPixelDimension = 3_200
    public static let maximumTextCharacters = 20_000

    private let queue = DispatchQueue(
        label: "Perch.ScreenshotOCR",
        qos: .utility
    )

    public init() {}

    public func recognizeText(at url: URL) async throws -> ScreenshotOCRResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try Self.performRecognition(at: url))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func recognizeText(in image: CGImage) async throws -> ScreenshotOCRResult {
        let boxedImage = SendableImage(image)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(
                        returning: try Self.performRecognition(in: boxedImage.image)
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func performRecognition(at url: URL) throws -> ScreenshotOCRResult {
        let image: CGImage = try autoreleasepool {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                throw ScreenshotOCRError.unreadableImage
            }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                throw ScreenshotOCRError.thumbnailCreationFailed
            }
            return image
        }
        return try performRecognition(in: image)
    }

    private static func performRecognition(in image: CGImage) throws -> ScreenshotOCRResult {
        let startedAt = DispatchTime.now().uptimeNanoseconds

        let recognition: (text: String?, lines: [RecognizedTextLine]) = try autoreleasepool {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0.006

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let recognizedLines = (request.results ?? []).compactMap {
                observation -> RecognizedTextLine? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= 0.25
                else {
                    return nil
                }
                let line = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                let box = observation.boundingBox
                return RecognizedTextLine(
                    text: line,
                    confidence: candidate.confidence,
                    minX: box.minX,
                    minY: box.minY,
                    width: box.width,
                    height: box.height
                )
            }
            .sorted {
                if abs($0.maxY - $1.maxY) > 0.01 {
                    return $0.maxY > $1.maxY
                }
                return $0.minX < $1.minX
            }

            guard !recognizedLines.isEmpty else { return (nil, []) }

            var boundedLines: [RecognizedTextLine] = []
            var characterCount = 0
            for line in recognizedLines {
                let addedCount = line.text.count + (boundedLines.isEmpty ? 0 : 1)
                guard characterCount + addedCount <= maximumTextCharacters else {
                    break
                }
                boundedLines.append(line)
                characterCount += addedCount
            }
            let text = boundedLines.map(\.text).joined(separator: "\n")
            return (text.isEmpty ? nil : text, boundedLines)
        }

        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return ScreenshotOCRResult(
            text: recognition.text,
            lines: recognition.lines,
            durationMilliseconds: Int64(elapsedNanoseconds / 1_000_000)
        )
    }
}

private final class SendableImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
