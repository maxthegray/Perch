import UniformTypeIdentifiers
import XCTest
@testable import Perch

final class FileTypeBadgeTests: XCTestCase {
    func testUsesTheFileExtension() {
        XCTAssertEqual(
            FileTypeBadgePresentation.label(
                backingFileNames: ["photo.jpg"],
                primaryFileType: UTType.jpeg.identifier
            ),
            "JPG"
        )
        XCTAssertEqual(
            FileTypeBadgePresentation.label(
                backingFileNames: ["one.png", "two.png"],
                primaryFileType: UTType.png.identifier
            ),
            "PNG"
        )
    }

    func testUsesTheContentTypeForAFileClipping() {
        XCTAssertEqual(
            FileTypeBadgePresentation.label(
                backingFileNames: [],
                primaryFileType: UTType.pdf.identifier
            ),
            "PDF"
        )
    }

    func testOmitsMixedFilesFoldersAndApplications() {
        XCTAssertNil(FileTypeBadgePresentation.label(
            backingFileNames: ["one.png", "two.pdf"],
            primaryFileType: nil
        ))
        XCTAssertNil(FileTypeBadgePresentation.label(
            backingFileNames: ["Documents"],
            primaryFileType: UTType.folder.identifier
        ))
        XCTAssertNil(FileTypeBadgePresentation.label(
            backingFileNames: ["Perch.app"],
            primaryFileType: UTType.applicationBundle.identifier
        ))
    }

    func testCompactsLongExtensions() {
        XCTAssertEqual(
            FileTypeBadgePresentation.label(
                backingFileNames: ["Budget.numbers"],
                primaryFileType: nil
            ),
            "NUM"
        )
    }
}
