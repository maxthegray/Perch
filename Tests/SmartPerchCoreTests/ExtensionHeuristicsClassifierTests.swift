import XCTest
@testable import SmartPerchCore

final class ExtensionHeuristicsClassifierTests: XCTestCase {
    private let classifier = ExtensionHeuristicsClassifier()

    func testRepresentativeExtensions() {
        let cases: [(String, FileCategory)] = [
            ("proposal.pdf", .document),
            ("Screenshot 2026-07-25 at 9.41.12 AM.PNG", .image),
            ("Perch.dmg", .installer),
            ("source.tar.gz", .archive),
            ("ShelfController.swift", .code),
            ("interview.m4a", .media),
            ("untyped.bin", .other)
        ]

        for (fileName, expectedCategory) in cases {
            XCTAssertEqual(
                classifier.classify(metadata(fileName)),
                expectedCategory,
                "Expected \(fileName) to be \(expectedCategory)"
            )
        }
    }

    func testCompoundArchiveExtensionIsRecognized() {
        XCTAssertEqual(classifier.classify(metadata("backup.TAR.XZ")), .archive)
    }

    func testExtensionTakesPriorityOverGenericContentType() {
        XCTAssertEqual(
            classifier.classify(
                metadata("script.swift", contentTypeIdentifier: "public.data")
            ),
            .code
        )
    }

    func testContentTypeClassifiesExtensionlessFile() {
        XCTAssertEqual(
            classifier.classify(
                metadata("scan", contentTypeIdentifier: "public.jpeg")
            ),
            .image
        )
    }

    func testKnownExtensionlessFileNames() {
        XCTAssertEqual(classifier.classify(metadata("Dockerfile")), .code)
        XCTAssertEqual(classifier.classify(metadata("README")), .document)
    }

    func testUnknownDirectoryDoesNotInventAFileCategory() {
        XCTAssertEqual(
            classifier.classify(metadata("Project", isDirectory: true)),
            .other
        )
        XCTAssertEqual(
            classifier.classify(metadata("Misleading.pdf", isDirectory: true)),
            .other
        )
    }

    func testKnownCodePackageIsCode() {
        XCTAssertEqual(
            classifier.classify(metadata("Perch.xcodeproj", isDirectory: true)),
            .code
        )
    }

    func testApplicationBundleIsAnInstallerEvenThoughItIsADirectory() {
        XCTAssertEqual(
            classifier.classify(
                metadata(
                    "Perch.app",
                    contentTypeIdentifier: "com.apple.application-bundle",
                    isDirectory: true
                )
            ),
            .installer
        )
    }

    private func metadata(
        _ fileName: String,
        contentTypeIdentifier: String? = nil,
        isDirectory: Bool? = false
    ) -> DroppedFileMetadata {
        DroppedFileMetadata(
            url: URL(fileURLWithPath: "/tmp").appendingPathComponent(fileName),
            contentTypeIdentifier: contentTypeIdentifier,
            byteCount: 1_024,
            isDirectory: isDirectory
        )
    }
}
