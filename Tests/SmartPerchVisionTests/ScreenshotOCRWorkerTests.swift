import AppKit
import Foundation
import XCTest
@testable import SmartPerchVision

final class ScreenshotOCRWorkerTests: XCTestCase {
    func testRecognizesTextFromDownsampledImage() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartPerchVisionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let imageURL = directoryURL.appendingPathComponent("Screenshot.png")
        try makeTestImage().write(to: imageURL)

        let result = try await ScreenshotOCRWorker().recognizeText(at: imageURL)
        let text = try XCTUnwrap(result.text?.uppercased())

        XCTAssertTrue(text.contains("SMART PERCH"))
        XCTAssertTrue(text.contains("4821"))
        XCTAssertFalse(result.lines.isEmpty)
        XCTAssertTrue(result.lines.allSatisfy { $0.height > 0 && $0.width > 0 })
        XCTAssertGreaterThanOrEqual(result.durationMilliseconds, 0)
        XCTAssertLessThanOrEqual(text.count, ScreenshotOCRWorker.maximumTextCharacters)
    }

    private func makeTestImage() throws -> Data {
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

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw TestImageError.encodingFailed
        }
        return png
    }
}

private enum TestImageError: Error {
    case encodingFailed
}
