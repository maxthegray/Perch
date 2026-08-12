import AppKit
import Foundation
import PDFKit
import SmartPerchCore
import SmartPerchVision

struct PDFSmartNameAnalyzer: Sendable {
    static let identifier = "pdf-visual-title"
    static let version = 1
    private static let maximumPages = 3

    private let ocrWorker: ScreenshotOCRWorker
    private let titleDetector = VisualTitleDetector()

    init(ocrWorker: ScreenshotOCRWorker = ScreenshotOCRWorker()) {
        self.ocrWorker = ocrWorker
    }

    func recognizeText(at url: URL) async -> ScreenshotOCRResult {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let embedded = await Task.detached(priority: .utility) {
            Self.embeddedText(at: url)
        }.value

        if let metadataTitle = embedded.metadataTitle {
            return Self.result(text: metadataTitle, startedAt: startedAt)
        }
        if let visualTitle = titleDetector.title(in: embedded.lines) {
            return Self.result(text: visualTitle, startedAt: startedAt)
        }
        if embedded.hasMeaningfulText {
            return Self.result(text: nil, startedAt: startedAt)
        }

        for pageIndex in 0..<embedded.pageCount {
            guard !Task.isCancelled else { break }
            guard let pageImage = await Task.detached(priority: .utility, operation: {
                Self.renderPage(at: pageIndex, from: url)
            }).value else {
                continue
            }
            guard let ocrResult = try? await ocrWorker.recognizeText(
                in: pageImage.image
            ) else {
                continue
            }
            guard let title = titleDetector.title(in: ocrResult.lines) else {
                continue
            }
            return Self.result(text: title, startedAt: startedAt)
        }
        return Self.result(text: nil, startedAt: startedAt)
    }

    private struct EmbeddedText: Sendable {
        let metadataTitle: String?
        let lines: [RecognizedTextLine]
        let pageCount: Int
        let hasMeaningfulText: Bool
    }

    private static func embeddedText(at url: URL) -> EmbeddedText {
        guard let document = PDFDocument(url: url) else {
            return EmbeddedText(
                metadataTitle: nil,
                lines: [],
                pageCount: 0,
                hasMeaningfulText: false
            )
        }
        let rawTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let firstPage = document.page(at: 0)
        let lines = firstPage.map(recognizedLines) ?? []
        return EmbeddedText(
            metadataTitle: usefulTitle(rawTitle, filename: url.lastPathComponent),
            lines: lines,
            pageCount: min(maximumPages, document.pageCount),
            hasMeaningfulText: alphabeticCount(
                in: lines.map(\.text).joined(separator: " ")
            ) >= 20
        )
    }

    private static func recognizedLines(on page: PDFPage) -> [RecognizedTextLine] {
        let pageBounds = page.bounds(for: .mediaBox)
        guard page.numberOfCharacters > 0,
              pageBounds.width > 0,
              pageBounds.height > 0,
              let selection = page.selection(
                  for: NSRange(location: 0, length: page.numberOfCharacters)
              ) else {
            return []
        }

        return selection.selectionsByLine().compactMap { lineSelection in
            guard let rawText = lineSelection.string else { return nil }
            let text = rawText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let bounds = lineSelection.bounds(for: page).intersection(pageBounds)
            guard !text.isEmpty,
                  !bounds.isNull,
                  bounds.width > 0,
                  bounds.height > 0 else {
                return nil
            }
            return RecognizedTextLine(
                text: text,
                confidence: 1,
                minX: (bounds.minX - pageBounds.minX) / pageBounds.width,
                minY: (bounds.minY - pageBounds.minY) / pageBounds.height,
                width: bounds.width / pageBounds.width,
                height: bounds.height / pageBounds.height
            )
        }
    }

    private static func renderPage(at index: Int, from url: URL) -> SendablePDFPageImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: index) else {
            return nil
        }
        let thumbnail = page.thumbnail(
            of: NSSize(width: 2_000, height: 2_000),
            for: .mediaBox
        )
        var proposedRect = CGRect(origin: .zero, size: thumbnail.size)
        guard let image = thumbnail.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        return SendablePDFPageImage(image)
    }

    private static func usefulTitle(_ rawTitle: String?, filename: String) -> String? {
        guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              VisualTitleDetector.isPlausibleTitleText(title) else {
            return nil
        }
        let filenameStem = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
        guard title.caseInsensitiveCompare("Untitled") != .orderedSame,
              title.caseInsensitiveCompare(filenameStem) != .orderedSame else {
            return nil
        }
        return title
    }

    private static func alphabeticCount(in text: String?) -> Int {
        text?.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.letters.contains(scalar) { count += 1 }
        } ?? 0
    }

    private static func result(
        text: String?,
        startedAt: UInt64
    ) -> ScreenshotOCRResult {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return ScreenshotOCRResult(
            text: text,
            lines: [],
            durationMilliseconds: Int64(elapsed / 1_000_000)
        )
    }
}

private final class SendablePDFPageImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
