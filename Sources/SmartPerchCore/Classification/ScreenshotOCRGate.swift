import Foundation

/// Conservative first-pass policy for deciding whether Vision OCR should run.
///
/// The macOS screen-capture extended attribute is authoritative when present.
/// Filename matching is a fallback for files whose metadata was stripped in transit.
public struct ScreenshotOCRGate: Sendable {
    public static let maximumByteCount: Int64 = 25 * 1_024 * 1_024

    public init() {}

    public func isEligible(
        _ metadata: DroppedFileMetadata,
        category: FileCategory
    ) -> Bool {
        guard category == .image,
              metadata.isDirectory != true,
              let byteCount = metadata.byteCount,
              byteCount > 0,
              byteCount <= Self.maximumByteCount,
              Self.supportedExtensions.contains(metadata.url.pathExtension.lowercased())
        else {
            return false
        }

        if metadata.isScreenCapture == true {
            return true
        }

        let fileName = metadata.url.deletingPathExtension().lastPathComponent.lowercased()
        return Self.fileNameMarkers.contains { fileName.contains($0) }
    }

    private static let supportedExtensions: Set<String> = [
        "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff"
    ]

    private static let fileNameMarkers: Set<String> = [
        "screen capture",
        "screen shot",
        "screen-capture",
        "screen-shot",
        "screen_capture",
        "screen_shot",
        "screencapture",
        "screenshot"
    ]
}
