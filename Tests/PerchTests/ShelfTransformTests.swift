import Combine
import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Perch

final class ShelfTransformTests: XCTestCase {
    func testOutputModeDefaultsToDuplicateAndPersistsReplace() {
        let suiteName = "ShelfTransformOutputModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ShelfTransformOutputMode.load(from: defaults), .duplicate)
        ShelfTransformOutputMode.replace.save(to: defaults)
        XCTAssertEqual(ShelfTransformOutputMode.load(from: defaults), .replace)
    }

    func testApplicabilityForImagesPDFsMixedAndSingleSelections() {
        let images = ShelfTransformSelection(operandTypes: [[.png], [.jpeg]])
        let pdfs = ShelfTransformSelection(operandTypes: [[.pdf], [.pdf]])
        let mixed = ShelfTransformSelection(operandTypes: [[.png], [.pdf]])
        let single = ShelfTransformSelection(operandTypes: [[.tiff]])
        let invalidMerge = ShelfTransformSelection(operandTypes: [[.png], [.plainText]])
        let singlePDF = ShelfTransformSelection(operandTypes: [[.pdf]])
        let onePagePDF = ShelfTransformSelection(
            operandTypes: [[.pdf]],
            canSplitSinglePDF: false
        )
        let multiFilePDFItem = ShelfTransformSelection(operandTypes: [[.pdf, .pdf]])
        let optimizableImages = ShelfTransformSelection(operandTypes: [[.jpeg], [.heic]])
        let videos = ShelfTransformSelection(operandTypes: [[.mpeg4Movie], [.quickTimeMovie]])
        let audio = ShelfTransformSelection(operandTypes: [[.mpeg4Audio]])
        let singleZIP = ShelfTransformSelection(operandTypes: [[.zip]])
        let multipleZIPs = ShelfTransformSelection(operandTypes: [[.zip], [.zip]])
        let mixedWithZIP = ShelfTransformSelection(operandTypes: [[.zip], [.plainText]])

        XCTAssertEqual(
            Set(ShelfTransformAction.availableActions(for: images)),
            expectedImageActions.union([.mergePDF])
        )
        XCTAssertEqual(ShelfTransformAction.availableActions(for: pdfs), [.mergePDF, .zip])
        XCTAssertEqual(ShelfTransformAction.availableActions(for: mixed), [.mergePDF, .zip])
        XCTAssertEqual(Set(ShelfTransformAction.availableActions(for: single)), expectedImageActions)
        XCTAssertEqual(ShelfTransformAction.availableActions(for: invalidMerge), [.zip])
        XCTAssertEqual(
            ShelfTransformAction.availableActions(for: singlePDF),
            [.splitPDF(PDFSplitPlan(breaksAfterPages: [])), .zip]
        )
        XCTAssertEqual(ShelfTransformAction.availableActions(for: onePagePDF), [.zip])
        XCTAssertEqual(ShelfTransformAction.availableActions(for: multiFilePDFItem), [.zip])
        XCTAssertEqual(
            Set(ShelfTransformAction.availableActions(for: optimizableImages)),
            expectedImageActions
                .union(ImageOptimizationPreset.allCases.map(ShelfTransformAction.optimize))
                .union([.mergePDF])
        )
        XCTAssertEqual(Set(ShelfTransformAction.availableActions(for: videos)), [.extractAudio, .zip])
        XCTAssertEqual(ShelfTransformAction.availableActions(for: audio), [.zip])
        XCTAssertTrue(ShelfTransformAction.availableActions(for: singleZIP).isEmpty)
        XCTAssertEqual(ShelfTransformAction.availableActions(for: multipleZIPs), [.zip])
        XCTAssertEqual(ShelfTransformAction.availableActions(for: mixedWithZIP), [.zip])
    }

    func testConversionWritesEveryRequestedTypeWithoutChangingSource() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImage(named: "photo.png", type: .png)
        let original = try Data(contentsOf: source)

        for format in ImageTransformFormat.allCases {
            let outputDirectory = fixture.outputDirectory.appendingPathComponent(
                format.rawValue,
                isDirectory: true
            )
            let events = await collect(
                .convert(format),
                input: fixture.input(for: source),
                outputDirectory: outputDirectory
            )
            let output = try XCTUnwrap(events.outputURL)
            let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))

            XCTAssertEqual(CGImageSourceGetType(outputSource) as String?, format.contentType.identifier)
        }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testOptimizePreservesJPEGAndReducesAHighQualitySource() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImage(
            named: "photo.jpg",
            type: .jpeg,
            width: 640,
            height: 480,
            compressionQuality: 1,
            patterned: true
        )
        let original = try Data(contentsOf: source)

        let events = await collect(
            .optimize(.balanced),
            input: fixture.input(for: source),
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))

        XCTAssertEqual(output.lastPathComponent, source.lastPathComponent)
        XCTAssertEqual(CGImageSourceGetType(outputSource) as String?, UTType.jpeg.identifier)
        XCTAssertLessThan(try Data(contentsOf: output).count, original.count)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testOptimizeSupportsEveryPresetForHEIC() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImage(
            named: "photo.heic",
            type: .heic,
            width: 320,
            height: 240,
            compressionQuality: 1,
            patterned: true
        )

        for preset in ImageOptimizationPreset.allCases {
            let outputDirectory = fixture.outputDirectory.appendingPathComponent(
                String(preset.rawValue),
                isDirectory: true
            )
            let events = await collect(
                .optimize(preset),
                input: fixture.input(for: source),
                outputDirectory: outputDirectory
            )
            let output = try XCTUnwrap(events.outputURL)
            let outputSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))

            XCTAssertEqual(CGImageSourceGetType(outputSource) as String?, UTType.heic.identifier)
        }
    }

    func testExtractAudioWritesM4AWithoutChangingSource() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makeAudio(named: "clip.wav")
        let original = try Data(contentsOf: source)

        let events = await collect(
            .extractAudio,
            input: fixture.input(for: source),
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let audioTracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)

        XCTAssertEqual(output.lastPathComponent, "clip.m4a")
        XCTAssertEqual(output.pathExtension, "m4a")
        XCTAssertFalse(audioTracks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testStripMetadataRemovesEXIFAndGPSWithoutChangingSource() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makeImage(
            named: "located.tiff",
            type: .tiff,
            exifAndGPS: true
        )
        let original = try Data(contentsOf: source)

        let events = await collect(
            .stripMetadata,
            input: fixture.input(for: source),
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let properties = try fixture.properties(of: output)

        XCTAssertNil(properties[kCGImagePropertyExifDictionary])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testMissingSourceProducesAnItemFailure() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let missing = fixture.root.appendingPathComponent("missing.png")
        let input = fixture.input(for: missing)

        let events = await collect(
            .convert(.jpeg),
            input: input,
            outputDirectory: fixture.outputDirectory
        )

        XCTAssertEqual(events.failureInputIDs, [input.id])
        XCTAssertNil(events.outputURL)
    }

    func testZipContainsExpectedFilesAndLeavesSourcesUntouched() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let first = try fixture.makeTextFile(named: "one.txt", contents: "one")
        let second = try fixture.makeTextFile(named: "two.txt", contents: "two")
        let inputs = [fixture.input(for: first), fixture.input(for: second)]

        let events = await collect(
            .zip,
            inputs: inputs,
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let archive = try Data(contentsOf: output)

        XCTAssertEqual(Array(archive.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(archive.range(of: Data("one.txt".utf8)))
        XCTAssertNotNil(archive.range(of: Data("two.txt".utf8)))
        XCTAssertEqual(try String(contentsOf: first), "one")
        XCTAssertEqual(try String(contentsOf: second), "two")
    }

    func testMergePDFPreservesDocumentAndPageOrder() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let first = try fixture.makePDF(named: "first.pdf", pageWidths: [101, 102])
        let second = try fixture.makePDF(named: "second.pdf", pageWidths: [201])
        let originals = try [first, second].map { try Data(contentsOf: $0) }

        let events = await collect(
            .mergePDF,
            inputs: [fixture.input(for: second), fixture.input(for: first)],
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let document = try XCTUnwrap(PDFDocument(url: output))
        let widths = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.bounds(for: .mediaBox).width
        }

        XCTAssertEqual(widths, [201, 101, 102])
        XCTAssertEqual(try Data(contentsOf: first), originals[0])
        XCTAssertEqual(try Data(contentsOf: second), originals[1])
    }

    func testMergePDFAcceptsMixedImageAndPDFInputs() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let image = try fixture.makeImage(named: "cover.png", type: .png)
        let pdf = try fixture.makePDF(named: "pages.pdf", pageWidths: [120, 130])
        let originals = try [image, pdf].map { try Data(contentsOf: $0) }

        let events = await collect(
            .mergePDF,
            inputs: [fixture.input(for: image), fixture.input(for: pdf)],
            outputDirectory: fixture.outputDirectory
        )
        let output = try XCTUnwrap(events.outputURL)
        let document = try XCTUnwrap(PDFDocument(url: output))

        XCTAssertEqual(document.pageCount, 3)
        XCTAssertEqual(try Data(contentsOf: image), originals[0])
        XCTAssertEqual(try Data(contentsOf: pdf), originals[1])
    }

    func testSplitPlanProducesOrderedPageRanges() {
        let plan = PDFSplitPlan(breaksAfterPages: [3, 1, 3, 0, 20])

        XCTAssertEqual(plan.breaksAfterPages, [1, 3, 20])
        XCTAssertEqual(plan.pageRanges(pageCount: 5), [0..<1, 1..<3, 3..<5])
    }

    func testSplitPDFWritesEachPartInOrderAndPreservesSource() async throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let source = try fixture.makePDF(
            named: "Document.pdf",
            pageWidths: [101, 102, 103, 104, 105]
        )
        let original = try Data(contentsOf: source)

        let events = await collect(
            .splitPDF(PDFSplitPlan(breaksAfterPages: [1, 3])),
            input: fixture.input(for: source),
            outputDirectory: fixture.outputDirectory
        )

        XCTAssertNil(events.aggregateFailure)
        XCTAssertEqual(events.outputURLs.map(\.lastPathComponent), [
            "Document 1.pdf",
            "Document 2.pdf",
            "Document 3.pdf"
        ])
        let widths = try events.outputURLs.map { output in
            let document = try XCTUnwrap(PDFDocument(url: output))
            return (0..<document.pageCount).compactMap {
                document.page(at: $0)?.bounds(for: .mediaBox).width
            }
        }
        XCTAssertEqual(widths, [[101], [102, 103], [104, 105]])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testMultiPagePDFPreviewReportsItsDocumentPageCount() throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let pdf = try fixture.makePDF(
            named: "twelve-pages.pdf",
            pageWidths: Array(repeating: 120, count: 12)
        )

        let count = MergePDFPreviewPageCounter.pageCount(for: [pdf])

        XCTAssertEqual(count, 12)
    }

    func testImagePreviewCountsAsOnePage() throws {
        let fixture = try TransformFixture()
        defer { fixture.remove() }
        let image = try fixture.makeImage(named: "cover.png", type: .png)

        XCTAssertEqual(MergePDFPreviewPageCounter.pageCount(for: [image]), 1)
    }

    private var expectedImageActions: Set<ShelfTransformAction> {
        Set(ImageTransformFormat.allCases.map(ShelfTransformAction.convert))
            .union([.stripMetadata, .zip])
    }

    private func collect(
        _ action: ShelfTransformAction,
        input: ShelfTransformInput,
        outputDirectory: URL
    ) async -> CollectedTransformEvents {
        await collect(action, inputs: [input], outputDirectory: outputDirectory)
    }

    private func collect(
        _ action: ShelfTransformAction,
        inputs: [ShelfTransformInput],
        outputDirectory: URL
    ) async -> CollectedTransformEvents {
        var collected = CollectedTransformEvents()
        for await event in action.run(inputs: inputs, outputDirectory: outputDirectory) {
            switch event {
            case let .output(_, fileURL):
                collected.outputURLs.append(fileURL)
            case let .failure(inputID, _, _, _):
                collected.failureInputIDs.append(inputID)
            case let .aggregateFailure(message):
                collected.aggregateFailure = message
            }
        }
        return collected
    }
}

@MainActor
final class ShelfTransformCoordinatorTests: XCTestCase {
    func testDefaultDuplicateKeepsSourceAndInsertsOwnedOutputAdjacent() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let source = try fixture.addReferencedImage(named: "source.png")
        let neighbor = try fixture.addOwnedImage(named: "neighbor.png")
        let original = try Data(contentsOf: source.backingFileURLs()[0])

        fixture.coordinator.perform(.convert(.jpeg), on: [source])

        XCTAssertEqual(fixture.interaction.transformPlaceholders.count, 1)
        XCTAssertEqual(fixture.store.items.map(\.id), [source.id, neighbor.id])
        let completed = await eventually {
            fixture.store.items.count == 3
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)

        let output = fixture.store.items[1]
        let outputURL = try XCTUnwrap(output.backingFileURLs().first)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        XCTAssertEqual(fixture.store.items.map(\.id), [source.id, output.id, neighbor.id])
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.jpeg.identifier)
        XCTAssertNil(output.metadata.referencedFiles)
        XCTAssertNotNil(source.metadata.referencedFiles)
        XCTAssertTrue(outputURL.path.hasPrefix(fixture.holding.itemsDir.path))
        XCTAssertFalse(source.backingFileURLs()[0].path.hasPrefix(fixture.holding.root.path))
        XCTAssertEqual(try Data(contentsOf: source.backingFileURLs()[0]), original)
        let cleanedUp = await eventually { fixture.transformWorkDirectoryIsEmpty }
        XCTAssertTrue(cleanedUp)
    }

    func testOptimizeShowsTheExactSizeChangeOnTheOutputRow() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let source = try fixture.addOwnedImage(named: "photo.jpg")

        fixture.coordinator.perform(.optimize(.balanced), on: [source])

        let completed = await eventually {
            fixture.store.items.count == 2
                && fixture.interaction.transformPlaceholders.isEmpty
                && fixture.interaction.transformResultDetails.count == 1
        }
        XCTAssertTrue(completed)
        let output = fixture.store.items[1]
        let detail = try XCTUnwrap(fixture.interaction.transformResultDetails[output.id])
        XCTAssertTrue(detail.contains("→"))
        XCTAssertTrue(
            detail.contains("smaller")
                || detail.contains("larger")
                || detail.contains("same size")
        )
    }

    func testReplaceRemovesReferenceRowWithoutTouchingExternalSource() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let source = try fixture.addReferencedImage(named: "referenced.png")
        let sourceURL = try XCTUnwrap(source.backingFileURLs().first)
        let original = try Data(contentsOf: sourceURL)
        var publishedItemIDs: [[UUID]] = []
        let cancellable = fixture.store.$items.dropFirst().sink { items in
            publishedItemIDs.append(items.map(\.id))
        }

        fixture.coordinator.perform(.convert(.jpeg), on: [source], outputMode: .replace)

        let placeholder = try XCTUnwrap(fixture.interaction.transformPlaceholders.first)
        XCTAssertTrue(placeholder.replacesSource)
        let pendingEntries = fixture.interaction.displayEntries(for: fixture.store.items)
        XCTAssertEqual(pendingEntries.count, 1)
        XCTAssertEqual(pendingEntries[0].id, .item(source.id))
        guard case .transform = pendingEntries[0] else {
            return XCTFail("Expected the working row to replace its source")
        }
        let completed = await eventually {
            fixture.store.items.count == 1
                && fixture.store.items[0].id != source.id
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        XCTAssertNil(fixture.store.items[0].metadata.referencedFiles)
        XCTAssertFalse(publishedItemIDs.contains { ids in
            ids.contains(source.id) && ids.count > 1
        })
        withExtendedLifetime(cancellable) {}
    }

    func testOutputCallbackRunsBeforeReplaceRemovesItsSource() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let source = try fixture.addOwnedImage(named: "source.png")
        var callbackAction: ShelfTransformAction?
        var callbackSourceIDs: [UUID] = []
        var sourceWasStillPresent = false

        fixture.coordinator.onProduceOutput = { action, sources, _ in
            callbackAction = action
            callbackSourceIDs = sources.map(\.id)
            sourceWasStillPresent = fixture.store.items.contains { $0.id == source.id }
        }
        fixture.coordinator.perform(
            .convert(.jpeg),
            on: [source],
            outputMode: .replace
        )

        let completed = await eventually {
            fixture.store.items.count == 1
                && fixture.store.items[0].id != source.id
                && callbackAction != nil
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(callbackAction, .convert(.jpeg))
        XCTAssertEqual(callbackSourceIDs, [source.id])
        XCTAssertTrue(sourceWasStillPresent)
    }

    func testReplaceRemovesSuccessfulSourceAndKeepsFailedSource() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let valid = try fixture.addOwnedImage(named: "valid.png")
        let validDirectory = valid.directoryURL
        let missing = try fixture.addMissingReference(named: "gone.png")

        fixture.coordinator.perform(
            .convert(.jpeg),
            on: [valid, missing],
            outputMode: .replace
        )

        XCTAssertEqual(fixture.interaction.transformPlaceholders.count, 2)
        let completed = await eventually {
            fixture.store.items.count == 2
                && !fixture.store.items.contains { $0.id == valid.id }
                && fixture.interaction.transformPlaceholders.count == 1
        }
        XCTAssertTrue(completed)

        let failure = try XCTUnwrap(fixture.interaction.transformPlaceholders.first)
        guard case let .failed(message) = failure.state else {
            return XCTFail("Expected a failed transform marker")
        }
        XCTAssertTrue(message.contains("no longer available"))
        XCTAssertEqual(failure.sourceItemID, missing.id)
        XCTAssertNotEqual(fixture.store.items[0].id, valid.id)
        XCTAssertEqual(fixture.store.items[1].id, missing.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: validDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: missing.directoryURL.path))
        let cleanedUp = await eventually { fixture.transformWorkDirectoryIsEmpty }
        XCTAssertTrue(cleanedUp)
    }

    func testReplaceZipRemovesAllSuccessfulSourceRows() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let first = try fixture.addOwnedTextFile(named: "one.txt", contents: "one")
        let second = try fixture.addOwnedTextFile(named: "two.txt", contents: "two")
        let sourceDirectories = [first.directoryURL, second.directoryURL]

        fixture.coordinator.perform(.zip, on: [first, second], outputMode: .replace)

        let completed = await eventually {
            fixture.store.items.count == 1
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        let archive = try XCTUnwrap(fixture.store.items.first)
        XCTAssertEqual(archive.metadata.backingFileNames, ["Archive.zip"])
        XCTAssertTrue(sourceDirectories.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
    }

    func testReplaceMergePDFUsesConfirmedOrderAndRemovesSources() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let first = try fixture.addOwnedPDF(named: "first.pdf", pageWidths: [101, 102])
        let second = try fixture.addOwnedPDF(named: "second.pdf", pageWidths: [201])
        let sourceDirectories = [first.directoryURL, second.directoryURL]
        var publishedItemIDs: [[UUID]] = []
        let cancellable = fixture.store.$items.dropFirst().sink { items in
            publishedItemIDs.append(items.map(\.id))
        }

        fixture.coordinator.perform(
            .mergePDF,
            on: [second, first],
            outputMode: .replace
        )

        let completed = await eventually {
            fixture.store.items.count == 1
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        let output = try XCTUnwrap(fixture.store.items.first?.backingFileURLs().first)
        XCTAssertEqual(output.lastPathComponent, "Merged.pdf")
        let document = try XCTUnwrap(PDFDocument(url: output))
        let widths = (0..<document.pageCount).compactMap {
            document.page(at: $0)?.bounds(for: .mediaBox).width
        }
        XCTAssertEqual(widths, [201, 101, 102])
        XCTAssertEqual(publishedItemIDs.count, 1)
        XCTAssertEqual(publishedItemIDs.first, fixture.store.items.map(\.id))
        XCTAssertTrue(sourceDirectories.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        })
        withExtendedLifetime(cancellable) {}
    }

    func testMergeOutputDoesNotTriggerTheDropLandingAnimation() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let first = try fixture.addOwnedPDF(named: "first.pdf", pageWidths: [101])
        let second = try fixture.addOwnedPDF(named: "second.pdf", pageWidths: [201])
        try? await Task.sleep(for: .milliseconds(100))
        var landingItemIDs: [UUID] = []
        let cancellable = fixture.store.$justAddedItemID.dropFirst().sink { itemID in
            if let itemID { landingItemIDs.append(itemID) }
        }

        fixture.coordinator.perform(.mergePDF, on: [first, second])

        let completed = await eventually {
            fixture.store.items.count == 3
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        XCTAssertTrue(landingItemIDs.isEmpty)
        withExtendedLifetime(cancellable) {}
    }

    func testSplitPDFPreservesSourceEvenWhenReplaceIsPreferred() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let source = try fixture.addOwnedPDF(
            named: "document.pdf",
            pageWidths: [101, 102, 103]
        )

        fixture.coordinator.perform(
            .splitPDF(PDFSplitPlan(breaksAfterPages: [1])),
            on: [source],
            outputMode: .replace
        )

        let completed = await eventually {
            fixture.store.items.count == 3
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        XCTAssertEqual(fixture.store.items.first?.id, source.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.directoryURL.path))
        XCTAssertEqual(
            fixture.store.items.dropFirst().flatMap(\.metadata.backingFileNames),
            ["document 1.pdf", "document 2.pdf"]
        )
    }

    func testCancellingMergeWindowCreatesNoOutputOrWorkingFiles() throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let first = try fixture.addOwnedPDF(named: "first.pdf", pageWidths: [101])
        let second = try fixture.addOwnedPDF(named: "second.pdf", pageWidths: [201])
        let windowController = MergePDFWindowController()
        var didConfirm = false
        windowController.show(items: [first, second]) { orderedItems in
            didConfirm = true
            fixture.coordinator.perform(.mergePDF, on: orderedItems)
        }
        let reorderController = try XCTUnwrap(NSApp.windows.first {
            $0.isVisible && $0.contentViewController is MergePDFViewController
        }?.contentViewController as? MergePDFViewController)

        reorderController.cancelOperation(nil)

        XCTAssertFalse(didConfirm)
        XCTAssertEqual(fixture.store.items.map(\.id), [first.id, second.id])
        XCTAssertTrue(fixture.interaction.transformPlaceholders.isEmpty)
        XCTAssertTrue(fixture.transformWorkDirectoryIsEmpty)
    }

    func testShutdownClearsTransientRowsAndWorkingFiles() throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        let workFile = fixture.holding.transformWorkDir.appendingPathComponent("partial")
        try Data("partial".utf8).write(to: workFile)
        fixture.interaction.addTransformPlaceholder(TransformPlaceholder(
            id: UUID(),
            sourceItemID: UUID(),
            title: "Working",
            state: .pending
        ))
        fixture.interaction.showTransformResultDetail("1 MB → 500 KB", for: UUID())

        fixture.coordinator.shutDown()

        XCTAssertTrue(fixture.interaction.transformPlaceholders.isEmpty)
        XCTAssertTrue(fixture.interaction.transformResultDetails.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.holding.transformWorkDir.path))
    }

    func testInitializationRemovesStaleWorkFromInterruptedRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShelfTransformStaleWorkTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let holding = HoldingDirectory(root: root.appendingPathComponent("Perch", isDirectory: true))
        let staleDirectory = holding.transformWorkDir.appendingPathComponent(
            "interrupted",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(
            to: staleDirectory.appendingPathComponent("output.partial")
        )
        try FileManager.default.createDirectory(at: holding.itemsDir, withIntermediateDirectories: true)
        let store = ItemStore(holding: holding)
        let interaction = RowInteractionState()

        _ = ShelfTransformCoordinator(
            holding: holding,
            store: store,
            snapshotter: PasteboardSnapshotter(holding: holding),
            interaction: interaction
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: holding.transformWorkDir.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            at: holding.transformWorkDir,
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    func testFortyImageBatchStartsPendingAndPublishesResultsIncrementally() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.remove() }
        var items: [StoredItem] = []
        for index in 0..<40 {
            items.append(try fixture.addOwnedImage(named: "image-\(index).png"))
        }
        var reachedFullPendingBatch = false
        var resultPendingCounts: [Int] = []
        let cancellable = fixture.interaction.$transformPlaceholders.sink { placeholders in
            let pendingCount = placeholders.filter {
                if case .pending = $0.state { return true }
                return false
            }.count
            if pendingCount == items.count {
                reachedFullPendingBatch = true
            } else if reachedFullPendingBatch {
                resultPendingCounts.append(pendingCount)
            }
        }

        fixture.coordinator.perform(.convert(.jpeg), on: items)

        XCTAssertEqual(fixture.store.items.count, 40)
        XCTAssertEqual(fixture.interaction.transformPlaceholders.count, 40)
        let completed = await eventually(timeout: .seconds(10)) {
            fixture.store.items.count == 80
                && fixture.interaction.transformPlaceholders.isEmpty
        }
        XCTAssertTrue(completed)
        XCTAssertTrue(resultPendingCounts.contains { $0 > 0 && $0 < items.count })
        withExtendedLifetime(cancellable) {}
    }

    private func eventually(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private struct CollectedTransformEvents {
    var outputURLs: [URL] = []
    var outputURL: URL? { outputURLs.last }
    var failureInputIDs: [UUID] = []
    var aggregateFailure: String?
}

private final class TransformFixture {
    let root: URL
    let outputDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShelfTransformTests-\(UUID().uuidString)",
            isDirectory: true
        )
        outputDirectory = root.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func input(for url: URL) -> ShelfTransformInput {
        ShelfTransformInput(
            id: UUID(),
            sourceItemID: UUID(),
            sourceURL: url,
            filename: url.lastPathComponent,
            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
        )
    }

    func makeTextFile(named name: String, contents: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func makePDF(named name: String, pageWidths: [CGFloat]) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        try writeTestPDF(to: url, pageWidths: pageWidths)
        return url
    }

    func makeImage(
        named name: String,
        type: UTType,
        width: Int = 8,
        height: Int = 6,
        orientation: Int? = nil,
        exifAndGPS: Bool = false,
        compressionQuality: Double? = nil,
        patterned: Bool = false
    ) throws -> URL {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        if patterned {
            for y in stride(from: 0, to: height, by: 8) {
                for x in stride(from: 0, to: width, by: 8) {
                    context.setFillColor(
                        red: CGFloat((x * 37 + y * 11) % 255) / 255,
                        green: CGFloat((x * 13 + y * 41) % 255) / 255,
                        blue: CGFloat((x * 29 + y * 17) % 255) / 255,
                        alpha: 1
                    )
                    context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        } else {
            context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let url = root.appendingPathComponent(name, isDirectory: false)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation ?? 1
        ]
        if let compressionQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = compressionQuality
        }
        if exifAndGPS {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifUserComment: "private"
            ]
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 42.0,
                kCGImagePropertyGPSLongitude: -71.0
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func makeAudio(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: false)
        let sampleRate = 44_100.0
        let frameCount = AVAudioFrameCount(sampleRate)
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            samples[frame] = sin(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.25
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func properties(of url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum TransformFixtureError: Error {
    case pdfWriteFailed
}

@MainActor
private final class CoordinatorFixture {
    let root: URL
    let holding: HoldingDirectory
    let store: ItemStore
    let interaction = RowInteractionState()
    let snapshotter: PasteboardSnapshotter
    let coordinator: ShelfTransformCoordinator

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ShelfTransformCoordinatorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        holding = HoldingDirectory(root: root.appendingPathComponent("Perch", isDirectory: true))
        try FileManager.default.createDirectory(at: holding.itemsDir, withIntermediateDirectories: true)
        store = ItemStore(holding: holding)
        snapshotter = PasteboardSnapshotter(holding: holding)
        coordinator = ShelfTransformCoordinator(
            holding: holding,
            store: store,
            snapshotter: snapshotter,
            interaction: interaction
        )
    }

    var transformWorkDirectoryIsEmpty: Bool {
        guard FileManager.default.fileExists(atPath: holding.transformWorkDir.path) else {
            return true
        }
        return (try? FileManager.default.contentsOfDirectory(
            at: holding.transformWorkDir,
            includingPropertiesForKeys: nil
        ).isEmpty) == true
    }

    func addOwnedImage(named name: String) throws -> StoredItem {
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(name, isDirectory: false)
        try writeImage(to: sourceURL)
        return try snapshotOwnedFile(sourceURL)
    }

    func addOwnedTextFile(named name: String, contents: String) throws -> StoredItem {
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(name, isDirectory: false)
        try Data(contents.utf8).write(to: sourceURL)
        return try snapshotOwnedFile(sourceURL)
    }

    func addOwnedPDF(named name: String, pageWidths: [CGFloat]) throws -> StoredItem {
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(name, isDirectory: false)
        try writeTestPDF(to: sourceURL, pageWidths: pageWidths)
        return try snapshotOwnedFile(sourceURL)
    }

    private func snapshotOwnedFile(_ sourceURL: URL) throws -> StoredItem {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("Perch.TransformCoordinatorTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        guard pasteboard.writeObjects([sourceURL as NSURL]) else {
            throw CoordinatorFixtureError.pasteboardWriteFailed
        }
        defer { pasteboard.clearContents() }
        let results = try snapshotter.snapshot(
            pasteboard,
            into: store,
            insertionIndex: store.items.count,
            referencesDroppedFiles: false
        )
        guard let item = results.first?.item else {
            throw CoordinatorFixtureError.snapshotFailed
        }
        return item
    }

    func addReferencedImage(named name: String) throws -> StoredItem {
        let sourceDirectory = root.appendingPathComponent("Referenced", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent(name, isDirectory: false)
        try writeImage(to: sourceURL)
        let directory = store.newItemDirectory()
        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(),
            title: name,
            representations: [],
            backingFileNames: [name],
            primaryFileType: UTType.png.identifier,
            originPaths: nil,
            referencedFiles: [name: ReferencedFile(url: sourceURL)]
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )
        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        store.insert(item, at: store.items.count)
        return item
    }

    func addMissingReference(named name: String) throws -> StoredItem {
        let missingURL = root
            .appendingPathComponent("Missing", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        let directory = store.newItemDirectory()
        let metadata = ItemMetadata(
            id: directory.id,
            createdAt: Date(),
            title: name,
            representations: [],
            backingFileNames: [name],
            primaryFileType: UTType.png.identifier,
            originPaths: nil,
            referencedFiles: [name: ReferencedFile(url: missingURL)]
        )
        try JSONEncoder().encode(metadata).write(
            to: directory.url.appendingPathComponent("meta.json"),
            options: .atomic
        )
        let item = StoredItem(metadata: metadata, directoryURL: directory.url)
        store.insert(item, at: store.items.count)
        return item
    }

    nonisolated func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeImage(to url: URL) throws {
        let width = 8
        let height = 6
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CoordinatorFixtureError.imageWriteFailed
        }
    }
}

private enum CoordinatorFixtureError: Error {
    case pasteboardWriteFailed
    case snapshotFailed
    case imageWriteFailed
}

private func writeTestPDF(to url: URL, pageWidths: [CGFloat]) throws {
    let document = PDFDocument()
    for width in pageWidths {
        let pixelWidth = max(1, Int(width.rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TransformFixtureError.pdfWriteFailed
        }
        context.setFillColor(red: 0.9, green: 0.9, blue: 0.92, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: 300))
        guard let cgImage = context.makeImage(),
              let page = PDFPage(image: NSImage(
                cgImage: cgImage,
                size: NSSize(width: width, height: 300)
              )) else {
            throw TransformFixtureError.pdfWriteFailed
        }
        page.setBounds(CGRect(x: 0, y: 0, width: width, height: 300), for: .mediaBox)
        document.insert(page, at: document.pageCount)
    }
    guard document.write(to: url) else {
        throw TransformFixtureError.pdfWriteFailed
    }
}
