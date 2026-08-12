import AppKit
import CoreText
import Foundation
import PDFKit
import SmartPerchCore
import XCTest
@testable import Perch

final class PDFSmartNameAnalyzerTests: XCTestCase {
    func testUsesEmbeddedTextWithoutOCRLayout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFSmartNameAnalyzerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        try writeTextPDF(to: url, text: "Quarterly Revenue Forecast")

        let result = await PDFSmartNameAnalyzer().recognizeText(at: url)

        XCTAssertTrue(result.text?.contains("Quarterly Revenue Forecast") == true)
        XCTAssertTrue(result.lines.isEmpty)
    }

    func testFallsBackToOCRForImageOnlyPDF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFSmartNameAnalyzerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scan.pdf")
        let image = NSImage(size: NSSize(width: 1_600, height: 500))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        NSString(string: "SMART PERCH INVOICE 4821").draw(
            at: NSPoint(x: 70, y: 170),
            withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 100),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        XCTAssertTrue(document.write(to: url))

        let result = await PDFSmartNameAnalyzer().recognizeText(at: url)

        let text = try XCTUnwrap(result.text?.uppercased())
        XCTAssertTrue(text.contains("SMART PERCH"))
        XCTAssertTrue(text.contains("4821"))
    }

    func testUsesVisualHierarchyInsteadOfExtractionOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PDFSmartNameAnalyzerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("2411.15287.pdf")
        try writeHierarchicalPDF(to: url)

        let result = await PDFSmartNameAnalyzer().recognizeText(at: url)

        XCTAssertEqual(
            result.text,
            "Sycophancy in Large Language Models: Causes and Mitigations"
        )
        XCTAssertEqual(
            ScreenshotFilenameSuggester().suggestName(
                from: result.text ?? "",
                originalFilename: url.lastPathComponent
            )?.displayName,
            "Sycophancy Large Language Models"
        )
    }

    private func writeTextPDF(to url: URL, text: String) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw PDFTestError.creationFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw PDFTestError.creationFailed
        }
        context.beginPDFPage(nil)
        draw(text, size: 28, at: CGPoint(x: 72, y: 680), in: context)
        context.endPDFPage()
        context.closePDF()
    }

    private func writeHierarchicalPDF(to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw PDFTestError.creationFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw PDFTestError.creationFailed
        }
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 28, y: 110)
        context.rotate(by: .pi / 2)
        draw(
            "arXiv:2411.15287v1 [cs.CL] 22 Nov 2024",
            size: 12,
            at: .zero,
            in: context
        )
        context.restoreGState()
        draw(
            "Sycophancy in Large Language Models: Causes",
            size: 24,
            at: CGPoint(x: 86, y: 640),
            in: context
        )
        draw(
            "and Mitigations",
            size: 24,
            at: CGPoint(x: 220, y: 608),
            in: context
        )
        draw(
            "Lars Malmqvist",
            size: 13,
            at: CGPoint(x: 250, y: 555),
            in: context
        )
        draw(
            "Large language models have demonstrated remarkable capabilities across tasks.",
            size: 10,
            at: CGPoint(x: 95, y: 470),
            in: context
        )
        draw(
            "This paper provides a technical survey of sycophancy and mitigation strategies.",
            size: 10,
            at: CGPoint(x: 95, y: 450),
            in: context
        )
        context.endPDFPage()
        context.closePDF()
    }

    private func draw(
        _ text: String,
        size: CGFloat,
        at point: CGPoint,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}

private enum PDFTestError: Error {
    case creationFailed
}
