import Foundation
import Darwin

/// The inexpensive metadata snapshot presented to the first-stage classifier.
///
/// Keeping this value separate from the file makes classification deterministic:
/// tests and future event replays do not need to touch the original file.
public struct DroppedFileMetadata: Equatable, Sendable {
    public let url: URL
    public let contentTypeIdentifier: String?
    public let byteCount: Int64?
    public let isDirectory: Bool?
    public let isScreenCapture: Bool?

    public init(
        url: URL,
        contentTypeIdentifier: String? = nil,
        byteCount: Int64? = nil,
        isDirectory: Bool? = nil,
        isScreenCapture: Bool? = nil
    ) {
        self.url = url
        self.contentTypeIdentifier = contentTypeIdentifier
        self.byteCount = byteCount
        self.isDirectory = isDirectory
        self.isScreenCapture = isScreenCapture
    }

    /// Capture metadata while the backing file is known to exist.
    ///
    /// File promises and deferred copy fallbacks must call this only after their
    /// materialization completes.
    public static func capture(from url: URL) throws -> DroppedFileMetadata {
        let values = try url.resourceValues(forKeys: [
            .contentTypeKey,
            .fileSizeKey,
            .isDirectoryKey
        ])

        return DroppedFileMetadata(
            url: url,
            contentTypeIdentifier: values.contentType?.identifier,
            byteCount: values.fileSize.map(Int64.init),
            isDirectory: values.isDirectory,
            isScreenCapture: screenCaptureAttribute(at: url)
        )
    }

    private static func screenCaptureAttribute(at url: URL) -> Bool? {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return "com.apple.metadata:kMDItemIsScreenCapture".withCString { name in
                errno = 0
                let size = getxattr(path, name, nil, 0, 0, 0)
                if size >= 0 { return true }
                if errno == ENOATTR { return false }
                return nil
            }
        }
    }
}
