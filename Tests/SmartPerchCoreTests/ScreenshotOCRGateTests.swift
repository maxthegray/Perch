import Foundation
import Darwin
import XCTest
@testable import SmartPerchCore

final class ScreenshotOCRGateTests: XCTestCase {
    private let gate = ScreenshotOCRGate()

    func testMetadataCaptureReadsMacOSScreenCaptureAttribute() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotOCRGateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("Localized Name.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)

        let attributeValue = Data("1".utf8)
        let result = fileURL.withUnsafeFileSystemRepresentation { path in
            "com.apple.metadata:kMDItemIsScreenCapture".withCString { name in
                attributeValue.withUnsafeBytes { bytes in
                    setxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        XCTAssertEqual(result, 0)

        let captured = try DroppedFileMetadata.capture(from: fileURL)
        XCTAssertEqual(captured.isScreenCapture, true)
    }

    func testScreenCaptureMetadataIsEligibleWithoutEnglishFileName() {
        XCTAssertTrue(
            gate.isEligible(
                metadata(
                    "Bildschirmfoto.png",
                    isScreenCapture: true
                ),
                category: .image
            )
        )
    }

    func testScreenshotFileNameIsFallbackWhenMetadataWasStripped() {
        XCTAssertTrue(
            gate.isEligible(
                metadata(
                    "Screenshot 2026-07-25 at 11.42.20 PM.png",
                    isScreenCapture: false
                ),
                category: .image
            )
        )
    }

    func testOrdinaryImageIsNotEligible() {
        XCTAssertFalse(
            gate.isEligible(
                metadata("vacation.png", isScreenCapture: false),
                category: .image
            )
        )
    }

    func testNonImageAndOversizedScreenshotAreNotEligible() {
        XCTAssertFalse(
            gate.isEligible(
                metadata("Screenshot.txt", isScreenCapture: true),
                category: .document
            )
        )
        XCTAssertFalse(
            gate.isEligible(
                metadata(
                    "Screenshot.png",
                    byteCount: ScreenshotOCRGate.maximumByteCount + 1,
                    isScreenCapture: true
                ),
                category: .image
            )
        )
    }

    private func metadata(
        _ fileName: String,
        byteCount: Int64 = 1_024,
        isScreenCapture: Bool
    ) -> DroppedFileMetadata {
        DroppedFileMetadata(
            url: URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName),
            contentTypeIdentifier: nil,
            byteCount: byteCount,
            isDirectory: false,
            isScreenCapture: isScreenCapture
        )
    }
}
