import Foundation
import UniformTypeIdentifiers

/// Cheap, synchronous first-stage classification based on names, extensions, and
/// already-captured type metadata. It never reads file contents.
public struct ExtensionHeuristicsClassifier: Sendable {
    /// Persist both values with results so classifications remain explainable after
    /// these rules evolve.
    public static let identifier = "extension-heuristics"
    public static let version = 1

    public init() {}

    public func classify(_ file: DroppedFileMetadata) -> FileCategory {
        let fileName = file.url.lastPathComponent.lowercased()
        let pathExtension = file.url.pathExtension.lowercased()

        if Self.installerExtensions.contains(where: { fileName.hasSuffix(".\($0)") })
            || file.contentTypeIdentifier.map(Self.installerTypeIdentifiers.contains) == true {
            return .installer
        }
        if Self.codePackageExtensions.contains(pathExtension) {
            return .code
        }
        if file.isDirectory == true {
            return .other
        }
        if Self.archiveExtensions.contains(where: { fileName.hasSuffix(".\($0)") }) {
            return .archive
        }

        if let category = Self.categoriesByExtension[pathExtension] {
            return category
        }

        if Self.codeFileNames.contains(fileName) {
            return .code
        }
        if Self.documentFileNames.contains(fileName) {
            return .document
        }

        guard
            let identifier = file.contentTypeIdentifier,
            let contentType = UTType(identifier)
        else {
            return .other
        }

        if contentType.conforms(to: .archive) {
            return .archive
        }
        if contentType.conforms(to: .sourceCode) {
            return .code
        }
        if contentType.conforms(to: .image) {
            return .image
        }
        if contentType.conforms(to: .audiovisualContent)
            || contentType.conforms(to: .audio)
            || contentType.conforms(to: .movie) {
            return .media
        }
        if contentType.conforms(to: .pdf) || contentType.conforms(to: .text) {
            return .document
        }

        return .other
    }

    private static let categoriesByExtension: [String: FileCategory] = {
        var result: [String: FileCategory] = [:]

        for fileExtension in documentExtensions {
            result[fileExtension] = .document
        }
        for fileExtension in imageExtensions {
            result[fileExtension] = .image
        }
        for fileExtension in installerExtensions {
            result[fileExtension] = .installer
        }
        for fileExtension in archiveExtensions {
            result[fileExtension] = .archive
        }
        for fileExtension in codeExtensions {
            result[fileExtension] = .code
        }
        for fileExtension in mediaExtensions {
            result[fileExtension] = .media
        }

        return result
    }()

    private static let documentExtensions: Set<String> = [
        "csv", "doc", "docx", "epub", "key", "keynote", "log", "md", "mobi",
        "numbers", "odp", "ods", "odt", "pages", "pdf", "ppt", "pptx", "rtf",
        "rtfd", "tex", "text", "tsv", "txt", "xls", "xlsx"
    ]

    private static let imageExtensions: Set<String> = [
        "ai", "arw", "avif", "bmp", "cr2", "dng", "gif", "heic", "heif", "ico",
        "jpeg", "jpg", "nef", "png", "psd", "raw", "sketch", "svg", "tif", "tiff",
        "webp"
    ]

    /// Compound suffixes are included because `URL.pathExtension` only returns the
    /// last component (for example, "gz" for "backup.tar.gz").
    private static let installerExtensions: Set<String> = [
        "apk", "app", "deb", "dmg", "exe", "ipa", "iso", "mobileconfig", "mpkg",
        "msi", "pkg", "rpm", "xip"
    ]

    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "cab", "gz", "lz", "lz4", "lzma", "rar", "tar", "tar.bz2",
        "tar.gz", "tar.xz", "tar.zst", "tbz", "tbz2", "tgz", "txz", "xz", "zip",
        "zst"
    ]

    private static let codeExtensions: Set<String> = [
        "bash", "c", "cc", "clj", "cmake", "cpp", "cs", "css", "dart", "dts",
        "editorconfig", "entitlements", "fish", "fs", "fsx", "go", "gradle", "graphql",
        "h", "hpp", "htm", "html", "ini", "ipynb", "java", "js", "jsx", "json",
        "kt", "kts", "less", "lua", "m", "mm", "php", "pl", "plist", "properties",
        "proto", "py", "r", "rb", "rs", "sass", "scala", "scss", "sh", "sql", "svelte",
        "swift", "toml", "ts", "tsx", "vue", "xcassets", "xcodeproj", "xcworkspace",
        "xml", "yaml", "yml", "zsh"
    ]

    private static let mediaExtensions: Set<String> = [
        "3gp", "aac", "aiff", "alac", "avi", "flac", "flv", "m4a", "m4v", "mkv",
        "mov", "mp3", "mp4", "mpeg", "mpg", "oga", "ogg", "ogv", "opus", "wav",
        "webm", "wma", "wmv"
    ]

    private static let codeFileNames: Set<String> = [
        ".env", ".gitattributes", ".gitignore", ".npmrc", "brewfile", "cartfile",
        "cmakelists.txt", "containerfile", "dockerfile", "gemfile", "justfile",
        "makefile", "meson.build", "package.resolved", "podfile", "rakefile"
    ]

    private static let documentFileNames: Set<String> = [
        "authors", "changelog", "copying", "license", "notice", "readme"
    ]

    private static let codePackageExtensions: Set<String> = [
        "playground", "xcassets", "xcodeproj", "xcworkspace"
    ]

    private static let installerTypeIdentifiers: Set<String> = [
        "com.apple.application-bundle",
        "com.apple.disk-image",
        "com.apple.installer-package-archive",
        "com.apple.xip-archive"
    ]
}
