import AppKit
import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct ShelfTransformSelection {
    let operandTypes: [[UTType]]
    let canSplitSinglePDF: Bool?

    init(operandTypes: [[UTType]], canSplitSinglePDF: Bool? = nil) {
        self.operandTypes = operandTypes
        self.canSplitSinglePDF = canSplitSinglePDF
    }

    var count: Int { operandTypes.count }

    var containsOnlyImages: Bool {
        !operandTypes.isEmpty && operandTypes.allSatisfy { types in
            !types.isEmpty && types.allSatisfy { $0.conforms(to: .image) }
        }
    }

    var containsOnlyPDFsAndImages: Bool {
        !operandTypes.isEmpty && operandTypes.allSatisfy { types in
            !types.isEmpty && types.allSatisfy {
                $0.conforms(to: .pdf) || $0.conforms(to: .image)
            }
        }
    }

    var isSinglePDFFile: Bool {
        guard operandTypes.count == 1, operandTypes[0].count == 1 else { return false }
        guard operandTypes[0][0].conforms(to: .pdf) else { return false }
        return canSplitSinglePDF ?? true
    }

    var isSingleZIPFile: Bool {
        operandTypes.count == 1
            && operandTypes[0].count == 1
            && operandTypes[0][0].conforms(to: .zip)
    }

    var containsOnlyOptimizableImages: Bool {
        !operandTypes.isEmpty && operandTypes.allSatisfy { types in
            !types.isEmpty && types.allSatisfy {
                $0.conforms(to: .jpeg) || $0.conforms(to: .heic)
            }
        }
    }

    var containsOnlyVideos: Bool {
        !operandTypes.isEmpty && operandTypes.allSatisfy { types in
            !types.isEmpty && types.allSatisfy { $0.conforms(to: .movie) }
        }
    }
}

struct PDFSplitPlan: Hashable, Sendable {
    let breaksAfterPages: [Int]

    init(breaksAfterPages: [Int]) {
        self.breaksAfterPages = Array(Set(breaksAfterPages.filter { $0 > 0 })).sorted()
    }

    func pageRanges(pageCount: Int) -> [Range<Int>] {
        guard pageCount > 0 else { return [] }
        let breaks = breaksAfterPages.filter { $0 < pageCount }
        let boundaries = [0] + breaks + [pageCount]
        return zip(boundaries, boundaries.dropFirst()).map { $0..<$1 }
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

enum ImageOptimizationPreset: Int, CaseIterable, Sendable {
    case smaller = 55
    case balanced = 72
    case highQuality = 88

    var quality: Double { Double(rawValue) / 100 }

    var displayName: String {
        switch self {
        case .smaller: return "Smaller"
        case .balanced: return "Balanced"
        case .highQuality: return "High Quality"
        }
    }
}

enum ShelfTransformAction: Hashable, Sendable {
    case convert(ImageTransformFormat)
    case optimize(ImageOptimizationPreset)
    case stripMetadata
    case extractAudio
    case splitPDF(PDFSplitPlan)
    case mergePDF
    case zip

    static var menuActions: [ShelfTransformAction] {
        ImageTransformFormat.allCases.map(Self.convert)
            + ImageOptimizationPreset.allCases.map(Self.optimize)
            + [
                .stripMetadata,
                .extractAudio,
                .splitPDF(PDFSplitPlan(breaksAfterPages: [])),
                .mergePDF,
                .zip
            ]
    }

    static func availableActions(for selection: ShelfTransformSelection) -> [ShelfTransformAction] {
        menuActions.filter { $0.isApplicable(to: selection) }
    }

    func isApplicable(to selection: ShelfTransformSelection) -> Bool {
        switch self {
        case .convert, .stripMetadata:
            return selection.containsOnlyImages
        case .optimize:
            return selection.containsOnlyOptimizableImages
        case .extractAudio:
            return selection.containsOnlyVideos
        case .splitPDF:
            return selection.isSinglePDFFile
        case .mergePDF:
            return selection.count >= 2 && selection.containsOnlyPDFsAndImages
        case .zip:
            return selection.count >= 1 && !selection.isSingleZIPFile
        }
    }

    var producesAggregateOutput: Bool {
        switch self {
        case .splitPDF, .mergePDF, .zip:
            return true
        default:
            return false
        }
    }

    var preservesSources: Bool {
        if case .splitPDF = self { return true }
        return false
    }

    func pendingTitle(for filename: String) -> String {
        switch self {
        case let .convert(format):
            return "Converting \(filename) to \(format.displayName)…"
        case let .optimize(preset):
            return "Optimizing \(filename) (\(preset.displayName))…"
        case .stripMetadata:
            return "Removing metadata from \(filename)…"
        case .extractAudio:
            return "Extracting audio from \(filename)…"
        case .splitPDF:
            return "Splitting \(filename)…"
        case .mergePDF:
            return "Creating Merged.pdf…"
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
                case let .splitPDF(plan):
                    Self.runSplitPDF(
                        inputs,
                        plan: plan,
                        outputDirectory: outputDirectory,
                        continuation: continuation
                    )
                case .mergePDF:
                    Self.runMergePDF(
                        inputs,
                        outputDirectory: outputDirectory,
                        continuation: continuation
                    )
                case .extractAudio:
                    for input in inputs {
                        guard !Task.isCancelled else { return }
                        do {
                            let output = try await Self.extractAudio(
                                from: input,
                                outputDirectory: outputDirectory
                            )
                            continuation.yield(.output(inputID: input.id, fileURL: output))
                        } catch is CancellationError {
                            return
                        } catch {
                            continuation.yield(.failure(
                                inputID: input.id,
                                sourceItemID: input.sourceItemID,
                                filename: input.filename,
                                message: error.localizedDescription
                            ))
                        }
                    }
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

        case let .optimize(preset):
            let contentType = try writableSourceType(source, filename: input.filename)
            guard contentType == UTType.jpeg.identifier
                    || contentType == UTType.heic.identifier else {
                throw ShelfTransformError.unsupportedOptimizationFormat(input.filename)
            }
            let desired = outputDirectory.appendingPathComponent(input.filename, isDirectory: false)
            return try writeFromSource(
                source,
                to: ItemStore.nonClobberingURL(for: desired),
                contentType: contentType,
                options: [kCGImageDestinationLossyCompressionQuality: preset.quality]
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

        case .extractAudio, .splitPDF, .mergePDF, .zip:
            throw ShelfTransformError.unsupportedOperation
        }
    }

    private static func extractAudio(
        from input: ShelfTransformInput,
        outputDirectory: URL
    ) async throws -> URL {
        guard FileManager.default.fileExists(atPath: input.sourceURL.path) else {
            throw ShelfTransformError.sourceMissing(input.filename)
        }
        let asset = AVURLAsset(url: input.sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ShelfTransformError.noAudioTrack(input.filename)
        }
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ), exporter.supportedFileTypes.contains(.m4a) else {
            throw ShelfTransformError.audioExportUnavailable(input.filename)
        }

        let base = input.sourceURL.deletingPathExtension().lastPathComponent
        let finalURL = ItemStore.nonClobberingURL(
            for: outputDirectory.appendingPathComponent("\(base).m4a", isDirectory: false)
        )
        let partialURL = outputDirectory.appendingPathComponent(
            ".\(base)-\(UUID().uuidString).partial.m4a",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: partialURL) }

        if #available(macOS 15.0, *) {
            try await exporter.export(to: partialURL, as: .m4a)
        } else {
            exporter.outputURL = partialURL
            exporter.outputFileType = .m4a
            let exporterBox = SendableAudioExporter(exporter)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    exporterBox.session.exportAsynchronously {
                        switch exporterBox.session.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: CancellationError())
                        default:
                            continuation.resume(throwing:
                                exporterBox.session.error
                                    ?? ShelfTransformError.audioExportFailed(input.filename)
                            )
                        }
                    }
                }
            } onCancel: {
                exporterBox.session.cancelExport()
            }
        }
        try FileManager.default.moveItem(at: partialURL, to: finalURL)
        return finalURL
    }

    private static func runMergePDF(
        _ inputs: [ShelfTransformInput],
        outputDirectory: URL,
        continuation: AsyncStream<ShelfTransformEvent>.Continuation
    ) {
        let merged = PDFDocument()
        let fileManager = FileManager.default

        for input in inputs {
            guard !Task.isCancelled else { return }
            do {
                guard fileManager.fileExists(atPath: input.sourceURL.path) else {
                    throw ShelfTransformError.sourceMissing(input.filename)
                }
                let type = input.typeIdentifier.flatMap(UTType.init)
                    ?? UTType(filenameExtension: input.sourceURL.pathExtension)
                if type?.conforms(to: .pdf) == true {
                    guard let source = PDFDocument(url: input.sourceURL),
                          source.pageCount > 0 else {
                        throw ShelfTransformError.unreadablePDF(input.filename)
                    }
                    let pages = (0..<source.pageCount).compactMap(source.page(at:))
                    guard pages.count == source.pageCount else {
                        throw ShelfTransformError.unreadablePDF(input.filename)
                    }
                    for page in pages {
                        merged.insert(page, at: merged.pageCount)
                    }
                } else if type?.conforms(to: .image) == true {
                    guard let image = NSImage(contentsOf: input.sourceURL),
                          let page = PDFPage(image: image) else {
                        throw ShelfTransformError.unreadableImage(input.filename)
                    }
                    merged.insert(page, at: merged.pageCount)
                } else {
                    throw ShelfTransformError.unsupportedMergeInput(input.filename)
                }
            } catch {
                continuation.yield(.failure(
                    inputID: input.id,
                    sourceItemID: input.sourceItemID,
                    filename: input.filename,
                    message: error.localizedDescription
                ))
            }
        }

        guard merged.pageCount > 0, !Task.isCancelled else {
            continuation.yield(.aggregateFailure("No available pages could be merged."))
            return
        }

        let finalURL = ItemStore.nonClobberingURL(
            for: outputDirectory.appendingPathComponent("Merged.pdf", isDirectory: false)
        )
        let partialURL = outputDirectory.appendingPathComponent(
            ".Merged-\(UUID().uuidString).partial.pdf",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: partialURL) }
        guard merged.write(to: partialURL) else {
            continuation.yield(.aggregateFailure(
                ShelfTransformError.writeFailed("Merged.pdf").localizedDescription
            ))
            return
        }
        do {
            try fileManager.moveItem(at: partialURL, to: finalURL)
            continuation.yield(.output(inputID: nil, fileURL: finalURL))
        } catch {
            continuation.yield(.aggregateFailure(error.localizedDescription))
        }
    }

    private static func runSplitPDF(
        _ inputs: [ShelfTransformInput],
        plan: PDFSplitPlan,
        outputDirectory: URL,
        continuation: AsyncStream<ShelfTransformEvent>.Continuation
    ) {
        guard let input = inputs.first, inputs.count == 1 else {
            continuation.yield(.aggregateFailure(
                ShelfTransformError.invalidPDFSplit.localizedDescription
            ))
            return
        }
        let fileManager = FileManager.default
        do {
            guard fileManager.fileExists(atPath: input.sourceURL.path) else {
                throw ShelfTransformError.sourceMissing(input.filename)
            }
            guard let source = PDFDocument(url: input.sourceURL), source.pageCount > 1 else {
                throw ShelfTransformError.unreadablePDF(input.filename)
            }
            let ranges = plan.pageRanges(pageCount: source.pageCount)
            guard ranges.count > 1 else {
                throw ShelfTransformError.invalidPDFSplit
            }

            let base = input.sourceURL.deletingPathExtension().lastPathComponent
            var outputs: [URL] = []
            for (index, range) in ranges.enumerated() {
                guard !Task.isCancelled else { return }
                let part = PDFDocument()
                for pageIndex in range {
                    guard let page = source.page(at: pageIndex) else {
                        throw ShelfTransformError.unreadablePDF(input.filename)
                    }
                    part.insert(page, at: part.pageCount)
                }

                let filename = "\(base) \(index + 1).pdf"
                let finalURL = ItemStore.nonClobberingURL(
                    for: outputDirectory.appendingPathComponent(filename, isDirectory: false)
                )
                let partialURL = outputDirectory.appendingPathComponent(
                    ".\(base)-\(index + 1)-\(UUID().uuidString).partial.pdf",
                    isDirectory: false
                )
                guard part.write(to: partialURL) else {
                    throw ShelfTransformError.writeFailed(filename)
                }
                try fileManager.moveItem(at: partialURL, to: finalURL)
                outputs.append(finalURL)
            }

            for output in outputs {
                continuation.yield(.output(inputID: nil, fileURL: output))
            }
        } catch {
            continuation.yield(.aggregateFailure(error.localizedDescription))
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

private final class SendableAudioExporter: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
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
    case unreadablePDF(String)
    case unsupportedMergeInput(String)
    case unsupportedOptimizationFormat(String)
    case noAudioTrack(String)
    case audioExportUnavailable(String)
    case audioExportFailed(String)
    case invalidPDFSplit
    case unwritableFormat(String)
    case writeFailed(String)
    case unsupportedOperation

    var errorDescription: String? {
        switch self {
        case let .sourceMissing(filename):
            return "The source file \(filename) is no longer available."
        case let .unreadableImage(filename):
            return "\(filename) could not be read as an image."
        case let .unreadablePDF(filename):
            return "\(filename) could not be read as a PDF."
        case let .unsupportedMergeInput(filename):
            return "\(filename) is not an image or PDF."
        case let .unsupportedOptimizationFormat(filename):
            return "\(filename) is not a JPEG or HEIC image."
        case let .noAudioTrack(filename):
            return "\(filename) does not contain an audio track."
        case let .audioExportUnavailable(filename):
            return "Audio cannot be extracted from \(filename) as M4A."
        case let .audioExportFailed(filename):
            return "The audio in \(filename) could not be extracted."
        case .invalidPDFSplit:
            return "Choose at least one place to split the PDF."
        case let .unwritableFormat(type):
            return "ImageIO cannot write the source format \(type)."
        case let .writeFailed(filename):
            return "\(filename) could not be written."
        case .unsupportedOperation:
            return "This transform is not supported."
        }
    }
}
