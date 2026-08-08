import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ShelfTransformSelection {
    let operandTypes: [[UTType]]

    var count: Int { operandTypes.count }

    var containsOnlyImages: Bool {
        !operandTypes.isEmpty && operandTypes.allSatisfy { types in
            !types.isEmpty && types.allSatisfy { $0.conforms(to: .image) }
        }
    }
}

enum ShelfTransformOutputMode: String, CaseIterable, Sendable {
    case duplicate
    case replace

    var displayName: String {
        switch self {
        case .duplicate: return "Duplicate"
        case .replace: return "Replace"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: PerchSettings.transformOutputMode),
              let mode = Self(rawValue: rawValue) else {
            return .duplicate
        }
        return mode
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: PerchSettings.transformOutputMode)
    }
}

enum ImageTransformFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case heic
    case tiff

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    var filenameExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }

    var contentType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }
}

enum ImageResizePreset: Int, CaseIterable, Sendable {
    case quarter = 25
    case half = 50
    case threeQuarters = 75

    var scale: Double { Double(rawValue) / 100 }
    var displayName: String { "\(rawValue)%" }
}

enum ShelfTransformAction: Hashable, Sendable {
    case convert(ImageTransformFormat)
    case resize(ImageResizePreset)
    case stripMetadata
    case zip

    static var menuActions: [ShelfTransformAction] {
        ImageTransformFormat.allCases.map(Self.convert)
            + ImageResizePreset.allCases.map(Self.resize)
            + [.stripMetadata, .zip]
    }

    static func availableActions(for selection: ShelfTransformSelection) -> [ShelfTransformAction] {
        menuActions.filter { $0.isApplicable(to: selection) }
    }

    func isApplicable(to selection: ShelfTransformSelection) -> Bool {
        switch self {
        case .convert, .resize, .stripMetadata:
            return selection.containsOnlyImages
        case .zip:
            return selection.count >= 1
        }
    }

    func pendingTitle(for filename: String) -> String {
        switch self {
        case let .convert(format):
            return "Converting \(filename) to \(format.displayName)…"
        case let .resize(preset):
            return "Resizing \(filename) to \(preset.displayName)…"
        case .stripMetadata:
            return "Removing metadata from \(filename)…"
        case .zip:
            return "Creating Archive.zip…"
        }
    }

    func run(
        inputs: [ShelfTransformInput],
        outputDirectory: URL
    ) -> AsyncStream<ShelfTransformEvent> {
        AsyncStream { continuation in
            let worker = Task.detached(priority: .userInitiated) {
                defer { continuation.finish() }
                guard !Task.isCancelled else { return }
                do {
                    try FileManager.default.createDirectory(
                        at: outputDirectory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    continuation.yield(.aggregateFailure(error.localizedDescription))
                    return
                }
                guard !Task.isCancelled else { return }

                switch self {
                case .zip:
                    Self.runZip(inputs, outputDirectory: outputDirectory, continuation: continuation)
                default:
                    for input in inputs {
                        guard !Task.isCancelled else { return }
                        do {
                            let output = try runImage(input, outputDirectory: outputDirectory)
                            continuation.yield(.output(inputID: input.id, fileURL: output))
                        } catch {
                            continuation.yield(.failure(
                                inputID: input.id,
                                sourceItemID: input.sourceItemID,
                                filename: input.filename,
                                message: error.localizedDescription
                            ))
                        }
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }

    private func runImage(
        _ input: ShelfTransformInput,
        outputDirectory: URL
    ) throws -> URL {
        guard FileManager.default.fileExists(atPath: input.sourceURL.path) else {
            throw ShelfTransformError.sourceMissing(input.filename)
        }
        guard let source = CGImageSourceCreateWithURL(input.sourceURL as CFURL, nil) else {
            throw ShelfTransformError.unreadableImage(input.filename)
        }

        switch self {
        case let .convert(format):
            let base = input.sourceURL.deletingPathExtension().lastPathComponent
            let desired = outputDirectory.appendingPathComponent(
                "\(base).\(format.filenameExtension)",
                isDirectory: false
            )
            let destination = ItemStore.nonClobberingURL(for: desired)
            var options: [CFString: Any] = [:]
            if format == .jpeg {
                options[kCGImageDestinationLossyCompressionQuality] = 0.85
            }
            return try writeFromSource(
                source,
                to: destination,
                contentType: format.contentType.identifier,
                options: options
            )

        case let .resize(preset):
            let dimensions = try sourceDimensions(source, filename: input.filename)
            let targetLongestEdge = max(1, Int((Double(max(dimensions.width, dimensions.height)) * preset.scale).rounded()))
            let image = try orientedThumbnail(
                source,
                maxPixelSize: targetLongestEdge,
                filename: input.filename
            )
            let contentType = try writableSourceType(source, filename: input.filename)
            let desired = outputDirectory.appendingPathComponent(input.filename, isDirectory: false)
            return try writeImage(
                image,
                to: ItemStore.nonClobberingURL(for: desired),
                contentType: contentType
            )

        case .stripMetadata:
            let dimensions = try sourceDimensions(source, filename: input.filename)
            let image = try orientedThumbnail(
                source,
                maxPixelSize: max(dimensions.width, dimensions.height),
                filename: input.filename
            )
            let contentType = try writableSourceType(source, filename: input.filename)
            let desired = outputDirectory.appendingPathComponent(input.filename, isDirectory: false)
            return try writeImage(
                image,
                to: ItemStore.nonClobberingURL(for: desired),
                contentType: contentType
            )

        case .zip:
            throw ShelfTransformError.unsupportedOperation
        }
    }

    private static func runZip(
        _ inputs: [ShelfTransformInput],
        outputDirectory: URL,
        continuation: AsyncStream<ShelfTransformEvent>.Continuation
    ) {
        let fileManager = FileManager.default
        let stagedDirectory = outputDirectory.appendingPathComponent("Archive", isDirectory: true)
        do {
            try fileManager.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        } catch {
            continuation.yield(.aggregateFailure(error.localizedDescription))
            return
        }

        var stagedCount = 0
        for input in inputs {
            guard !Task.isCancelled else { return }
            guard fileManager.fileExists(atPath: input.sourceURL.path) else {
                continuation.yield(.failure(
                    inputID: input.id,
                    sourceItemID: input.sourceItemID,
                    filename: input.filename,
                    message: ShelfTransformError.sourceMissing(input.filename).localizedDescription
                ))
                continue
            }
            let desired = stagedDirectory.appendingPathComponent(input.filename, isDirectory: false)
            let destination = ItemStore.nonClobberingURL(for: desired)
            do {
                try fileManager.copyItem(at: input.sourceURL, to: destination)
                stagedCount += 1
            } catch {
                continuation.yield(.failure(
                    inputID: input.id,
                    sourceItemID: input.sourceItemID,
                    filename: input.filename,
                    message: error.localizedDescription
                ))
            }
        }

        guard stagedCount > 0, !Task.isCancelled else {
            continuation.yield(.aggregateFailure("No available files could be added to the archive."))
            return
        }

        let finalURL = ItemStore.nonClobberingURL(
            for: outputDirectory.appendingPathComponent("Archive.zip", isDirectory: false)
        )
        let partialURL = outputDirectory.appendingPathComponent(
            ".Archive-\(UUID().uuidString).partial",
            isDirectory: false
        )
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(
            readingItemAt: stagedDirectory,
            options: .forUploading,
            error: &coordinationError
        ) { archiveURL in
            do {
                try fileManager.copyItem(at: archiveURL, to: partialURL)
                try fileManager.moveItem(at: partialURL, to: finalURL)
            } catch {
                copyError = error
            }
        }
        try? fileManager.removeItem(at: partialURL)

        if let error = coordinationError ?? copyError as NSError? {
            continuation.yield(.aggregateFailure(error.localizedDescription))
        } else {
            continuation.yield(.output(inputID: nil, fileURL: finalURL))
        }
    }

    private func writeFromSource(
        _ source: CGImageSource,
        to destinationURL: URL,
        contentType: String,
        options: [CFString: Any]
    ) throws -> URL {
        let partialURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent)-\(UUID().uuidString).partial",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: partialURL) }
        guard let destination = CGImageDestinationCreateWithURL(
            partialURL as CFURL,
            contentType as CFString,
            1,
            nil
        ) else {
            throw ShelfTransformError.unwritableFormat(contentType)
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ShelfTransformError.writeFailed(destinationURL.lastPathComponent)
        }
        try FileManager.default.moveItem(at: partialURL, to: destinationURL)
        return destinationURL
    }

    private func writeImage(
        _ image: CGImage,
        to destinationURL: URL,
        contentType: String
    ) throws -> URL {
        let partialURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent)-\(UUID().uuidString).partial",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: partialURL) }
        guard let destination = CGImageDestinationCreateWithURL(
            partialURL as CFURL,
            contentType as CFString,
            1,
            nil
        ) else {
            throw ShelfTransformError.unwritableFormat(contentType)
        }
        var options: [CFString: Any] = [:]
        if contentType == UTType.jpeg.identifier {
            options[kCGImageDestinationLossyCompressionQuality] = 0.85
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ShelfTransformError.writeFailed(destinationURL.lastPathComponent)
        }
        try FileManager.default.moveItem(at: partialURL, to: destinationURL)
        return destinationURL
    }

    private func sourceDimensions(
        _ source: CGImageSource,
        filename: String
    ) throws -> (width: Int, height: Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw ShelfTransformError.unreadableImage(filename)
        }
        return (width, height)
    }

    private func orientedThumbnail(
        _ source: CGImageSource,
        maxPixelSize: Int,
        filename: String
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ShelfTransformError.unreadableImage(filename)
        }
        return image
    }

    private func writableSourceType(
        _ source: CGImageSource,
        filename: String
    ) throws -> String {
        guard let type = CGImageSourceGetType(source) as String? else {
            throw ShelfTransformError.unreadableImage(filename)
        }
        return type
    }
}

struct ShelfTransformInput: Sendable {
    let id: UUID
    let sourceItemID: UUID
    let sourceURL: URL
    let filename: String
    let typeIdentifier: String?
}

enum ShelfTransformEvent: Sendable {
    case output(inputID: UUID?, fileURL: URL)
    case failure(inputID: UUID, sourceItemID: UUID, filename: String, message: String)
    case aggregateFailure(String)
}

private enum ShelfTransformError: LocalizedError {
    case sourceMissing(String)
    case unreadableImage(String)
    case unwritableFormat(String)
    case writeFailed(String)
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(filename):
            return "The source file \(filename) is no longer available."
        case let .unreadableImage(filename):
            return "\(filename) could not be read as an image."
        case let .unwritableFormat(type):
            return "ImageIO cannot write the source format \(type)."
        case let .writeFailed(filename):
            return "\(filename) could not be written."
        case .unsupportedOperation:
            return "This transform is not supported."
        }
    }
}
