import Foundation

/// Presentation-only screenshot recognition used before OCR has produced a Smart Name.
///
/// The actual OCR gate also checks file metadata and image type. This lightweight
/// filename check exists so the first rendered frame can avoid exposing macOS's long
/// timestamp filename while the asynchronous metadata/OCR pipeline starts.
enum ScreenshotNamePresentation {
    static let placeholder = "Screenshot"

    static func filenameLooksLikeScreenshot(_ filename: String) -> Bool {
        let stem = URL(fileURLWithPath: filename)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        return markers.contains { stem.contains($0) }
    }

    private static let markers: Set<String> = [
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
