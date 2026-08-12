import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class ShelfTransformCoordinator {
    private struct Operation {
        let action: ShelfTransformAction
        let outputMode: ShelfTransformOutputMode
        let aggregatePlaceholderID: UUID?
        let insertionAnchorItemID: UUID
        let fallbackInsertionIndex: Int
        let orderedSourceItems: [StoredItem]
        let sourceItemsByID: [UUID: StoredItem]
        let inputsByID: [UUID: ShelfTransformInput]
        let sourceIDByInputID: [UUID: UUID]
        let expectedInputCountsBySource: [UUID: Int]
        var insertionOffsetsBySource: [UUID: Int] = [:]
        var successfulInputCountsBySource: [UUID: Int] = [:]
        var failedSourceIDs: Set<UUID> = []
        var aggregateOutputInserted = false
    }

    private let holding: HoldingDirectory
    private let store: ItemStore
    private let snapshotter: PasteboardSnapshotter
    private let interaction: RowInteractionState
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var operations: [UUID: Operation] = [:]
    private var isShuttingDown = false

    var onProduceOutput: ((ShelfTransformAction, [StoredItem], StoredItem) -> Void)?

    init(
        holding: HoldingDirectory,
        store: ItemStore,
        snapshotter: PasteboardSnapshotter,
        interaction: RowInteractionState
    ) {
        self.holding = holding
        self.store = store
        self.snapshotter = snapshotter
        self.interaction = interaction
        prepareWorkDirectory()
    }

    func perform(
        _ action: ShelfTransformAction,
        on items: [StoredItem],
        outputMode: ShelfTransformOutputMode = .duplicate
    ) {
        guard !isShuttingDown, !items.isEmpty else { return }
        let selection = Self.selection(for: items)
        guard action.isApplicable(to: selection) else { return }
        let effectiveOutputMode: ShelfTransformOutputMode = action.preservesSources
            ? .duplicate
            : outputMode

        let inputs = Self.inputs(for: items)
        let expectedInputCountsBySource = Dictionary(
            grouping: inputs,
            by: \.sourceItemID
        ).mapValues(\.count)
        let operationID = UUID()
        let operationDirectory = holding.transformWorkDir.appendingPathComponent(
            operationID.uuidString,
            isDirectory: true
        )
        let orderedSourceIDs = items.map(\.id)
        let selectedSourceIDs = Set(orderedSourceIDs)
        let insertionAnchorItemID = store.items.last {
            selectedSourceIDs.contains($0.id)
        }?.id ?? orderedSourceIDs.last ?? items[0].id
        let fallbackInsertionIndex = min(
            store.items.count,
            (store.items.firstIndex { $0.id == insertionAnchorItemID } ?? 0) + 1
        )

        let aggregatePlaceholderID: UUID?
        if action.producesAggregateOutput {
            let id = UUID()
            aggregatePlaceholderID = id
            interaction.addTransformPlaceholder(TransformPlaceholder(
                id: id,
                sourceItemID: insertionAnchorItemID,
                title: action.pendingTitle(for: "Archive.zip"),
                state: .pending
            ))
        } else {
            aggregatePlaceholderID = nil
            for input in inputs {
                interaction.addTransformPlaceholder(TransformPlaceholder(
                    id: input.id,
                    sourceItemID: input.sourceItemID,
                    title: action.pendingTitle(for: input.filename),
                    replacesSource: effectiveOutputMode == .replace
                        && expectedInputCountsBySource[input.sourceItemID] == 1,
                    state: .pending
                ))
            }
        }

        operations[operationID] = Operation(
            action: action,
            outputMode: effectiveOutputMode,
            aggregatePlaceholderID: aggregatePlaceholderID,
            insertionAnchorItemID: insertionAnchorItemID,
            fallbackInsertionIndex: fallbackInsertionIndex,
            orderedSourceItems: items,
            sourceItemsByID: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }),
            inputsByID: Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) }),
            sourceIDByInputID: Dictionary(uniqueKeysWithValues: inputs.map {
                ($0.id, $0.sourceItemID)
            }),
            expectedInputCountsBySource: expectedInputCountsBySource
        )

        tasks[operationID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: operationDirectory)
                self.tasks[operationID] = nil
                self.operations[operationID] = nil
            }
            for await event in action.run(inputs: inputs, outputDirectory: operationDirectory) {
                guard !Task.isCancelled, !self.isShuttingDown else { return }
                self.handle(event, operationID: operationID)
                await Task.yield()
            }
            guard !Task.isCancelled, !self.isShuttingDown else { return }
            self.finish(operationID: operationID)
        }
    }

    func shutDown() {
        isShuttingDown = true
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        operations.removeAll()
        interaction.clearTransformPlaceholders()
        interaction.clearTransformResultDetails()
        try? FileManager.default.removeItem(at: holding.transformWorkDir)
    }

    static func selection(for items: [StoredItem]) -> ShelfTransformSelection {
        let operandTypes = items.map { item in
            let urls = item.backingFileURLs()
            let resolvedTypes = urls.compactMap(contentType)
            if !resolvedTypes.isEmpty {
                return resolvedTypes
            }
            if let identifier = item.metadata.primaryFileType,
               let type = UTType(identifier) {
                return [type]
            }
            return []
        }
        let canSplitSinglePDF: Bool?
        if items.count == 1,
           let types = operandTypes.first,
           types.count == 1,
           types[0].conforms(to: .pdf),
           let url = items[0].backingFileURLs().first {
            canSplitSinglePDF = (PDFDocument(url: url)?.pageCount ?? 0) > 1
        } else {
            canSplitSinglePDF = nil
        }
        return ShelfTransformSelection(
            operandTypes: operandTypes,
            canSplitSinglePDF: canSplitSinglePDF
        )
    }

    private static func inputs(for items: [StoredItem]) -> [ShelfTransformInput] {
        items.flatMap { item -> [ShelfTransformInput] in
            let urls = item.backingFileURLs()
            if urls.isEmpty {
                let filename = item.metadata.backingFileNames.first ?? item.metadata.title
                let missingURL = item.directoryURL
                    .appendingPathComponent("files", isDirectory: true)
                    .appendingPathComponent(filename, isDirectory: false)
                return [ShelfTransformInput(
                    id: UUID(),
                    sourceItemID: item.id,
                    sourceURL: missingURL,
                    filename: filename,
                    typeIdentifier: item.metadata.primaryFileType
                )]
            }
            return urls.enumerated().map { index, url in
                let filename = item.metadata.backingFileNames.indices.contains(index)
                    ? item.metadata.backingFileNames[index]
                    : url.lastPathComponent
                return ShelfTransformInput(
                    id: UUID(),
                    sourceItemID: item.id,
                    sourceURL: url,
                    filename: filename,
                    typeIdentifier: contentType(for: url)?.identifier
                )
            }
        }
    }

    private static func contentType(for url: URL) -> UTType? {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
    }

    private func handle(_ event: ShelfTransformEvent, operationID: UUID) {
        guard var operation = operations[operationID] else { return }
        switch event {
        case let .output(inputID, fileURL):
            let placeholderID = inputID ?? operation.aggregatePlaceholderID
            let sourceItemID = inputID.flatMap { operation.sourceIDByInputID[$0] }
                ?? operation.insertionAnchorItemID
            let offset = operation.insertionOffsetsBySource[sourceItemID, default: 0]
            let insertionIndex: Int
            if let sourceIndex = store.items.firstIndex(where: { $0.id == sourceItemID }) {
                insertionIndex = sourceIndex + 1 + offset
            } else {
                insertionIndex = min(store.items.count, operation.fallbackInsertionIndex + offset)
            }
            do {
                let resultDetail = inputID.flatMap { inputID in
                    operation.inputsByID[inputID].flatMap { input in
                        Self.optimizationResultDetail(
                            for: operation.action,
                            sourceURL: input.sourceURL,
                            outputURL: fileURL
                        )
                    }
                }
                let replacesSingleInputSource = operation.outputMode == .replace
                    && !operation.action.producesAggregateOutput
                    && operation.expectedInputCountsBySource[sourceItemID] == 1
                let replacesAggregateSources = operation.outputMode == .replace
                    && operation.action.producesAggregateOutput
                let output = try snapshotter.snapshotOwnedFile(
                    fileURL,
                    into: store,
                    at: insertionIndex,
                    insertsIntoStore: false
                )
                let outputSources: [StoredItem]
                if let source = operation.sourceItemsByID[sourceItemID], inputID != nil {
                    outputSources = [source]
                } else {
                    outputSources = operation.orderedSourceItems
                }
                onProduceOutput?(operation.action, outputSources, output)
                if let placeholderID {
                    interaction.removeTransformPlaceholder(placeholderID)
                }
                if replacesSingleInputSource,
                   let source = operation.sourceItemsByID[sourceItemID] {
                    if store.replace(source, with: output) {
                        interaction.removeFromSelection([sourceItemID])
                    } else {
                        store.insert(output, at: insertionIndex, animatesLanding: false)
                    }
                } else if replacesAggregateSources {
                    let replaceableSources = operation.sourceItemsByID.values.filter {
                        !operation.failedSourceIDs.contains($0.id)
                    }
                    if store.replace(
                        replaceableSources,
                        with: output,
                        after: operation.insertionAnchorItemID
                    ) {
                        interaction.removeFromSelection(Set(replaceableSources.map(\.id)))
                    } else {
                        store.insert(output, at: insertionIndex, animatesLanding: false)
                    }
                } else {
                    store.insert(output, at: insertionIndex, animatesLanding: false)
                }
                if let resultDetail {
                    interaction.showTransformResultDetail(resultDetail, for: output.id)
                }
                operation.insertionOffsetsBySource[sourceItemID, default: 0] += 1
                if inputID != nil {
                    operation.successfulInputCountsBySource[sourceItemID, default: 0] += 1
                } else {
                    operation.aggregateOutputInserted = true
                }
                operations[operationID] = operation
            } catch {
                operation.failedSourceIDs.insert(sourceItemID)
                operations[operationID] = operation
                if let placeholderID {
                    interaction.failTransformPlaceholder(
                        placeholderID,
                        message: error.localizedDescription
                    )
                }
            }

        case let .failure(inputID, sourceItemID, filename, message):
            operation.failedSourceIDs.insert(sourceItemID)
            operations[operationID] = operation
            if interaction.transformPlaceholders.contains(where: { $0.id == inputID }) {
                interaction.failTransformPlaceholder(inputID, message: message)
            } else {
                interaction.addTransformPlaceholder(TransformPlaceholder(
                    id: inputID,
                    sourceItemID: sourceItemID,
                    title: filename,
                    state: .failed(message)
                ))
            }

        case let .aggregateFailure(message):
            if let placeholderID = operation.aggregatePlaceholderID {
                interaction.failTransformPlaceholder(placeholderID, message: message)
            }
        }
    }

    private func finish(operationID: UUID) {
        guard let operation = operations[operationID],
              operation.outputMode == .replace else { return }

        let replaceableSourceIDs: Set<UUID>
        if operation.action.producesAggregateOutput {
            guard operation.aggregateOutputInserted else { return }
            replaceableSourceIDs = Set(operation.sourceItemsByID.keys).subtracting(
                operation.failedSourceIDs
            )
        } else {
            replaceableSourceIDs = Set(operation.sourceItemsByID.keys.filter { sourceID in
                !operation.failedSourceIDs.contains(sourceID)
                    && operation.successfulInputCountsBySource[sourceID]
                        == operation.expectedInputCountsBySource[sourceID]
            })
        }

        let replaceableItems = store.items.filter {
            replaceableSourceIDs.contains($0.id)
                && operation.sourceItemsByID[$0.id] != nil
        }
        guard !replaceableItems.isEmpty else { return }
        store.remove(replaceableItems)
        interaction.removeFromSelection(Set(replaceableItems.map(\.id)))
    }

    private static func optimizationResultDetail(
        for action: ShelfTransformAction,
        sourceURL: URL,
        outputURL: URL
    ) -> String? {
        guard case .optimize = action,
              let sourceBytes = fileSize(at: sourceURL),
              let outputBytes = fileSize(at: outputURL),
              sourceBytes > 0 else { return nil }

        let before = ByteCountFormatter.string(
            fromByteCount: sourceBytes,
            countStyle: .file
        )
        let after = ByteCountFormatter.string(
            fromByteCount: outputBytes,
            countStyle: .file
        )
        let change = Int((abs(Double(outputBytes - sourceBytes)) / Double(sourceBytes) * 100).rounded())
        if change == 0 {
            return "\(before) → \(after) · same size"
        }
        return outputBytes < sourceBytes
            ? "\(before) → \(after) · \(change)% smaller"
            : "\(before) → \(after) · \(change)% larger"
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(size)
    }

    private func prepareWorkDirectory() {
        try? FileManager.default.removeItem(at: holding.transformWorkDir)
        try? FileManager.default.createDirectory(
            at: holding.transformWorkDir,
            withIntermediateDirectories: true
        )
    }
}
