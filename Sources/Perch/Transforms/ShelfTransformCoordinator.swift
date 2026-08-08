import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShelfTransformCoordinator {
    private struct Operation {
        let action: ShelfTransformAction
        let outputMode: ShelfTransformOutputMode
        let aggregatePlaceholderID: UUID?
        let insertionAnchorItemID: UUID
        let fallbackInsertionIndex: Int
        let sourceItemsByID: [UUID: StoredItem]
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

        let inputs = Self.inputs(for: items)
        let operationID = UUID()
        let operationDirectory = holding.transformWorkDir.appendingPathComponent(
            operationID.uuidString,
            isDirectory: true
        )
        let orderedSourceIDs = items.map(\.id)
        let insertionAnchorItemID = orderedSourceIDs.last ?? items[0].id
        let fallbackInsertionIndex = min(
            store.items.count,
            (store.items.firstIndex { $0.id == insertionAnchorItemID } ?? 0) + 1
        )

        let aggregatePlaceholderID: UUID?
        if action == .zip {
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
                    state: .pending
                ))
            }
        }

        operations[operationID] = Operation(
            action: action,
            outputMode: outputMode,
            aggregatePlaceholderID: aggregatePlaceholderID,
            insertionAnchorItemID: insertionAnchorItemID,
            fallbackInsertionIndex: fallbackInsertionIndex,
            sourceItemsByID: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }),
            sourceIDByInputID: Dictionary(uniqueKeysWithValues: inputs.map {
                ($0.id, $0.sourceItemID)
            }),
            expectedInputCountsBySource: Dictionary(
                grouping: inputs,
                by: \.sourceItemID
            ).mapValues(\.count)
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
        try? FileManager.default.removeItem(at: holding.transformWorkDir)
    }

    static func selection(for items: [StoredItem]) -> ShelfTransformSelection {
        ShelfTransformSelection(operandTypes: items.map { item in
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
        })
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
                _ = try snapshotter.snapshotOwnedFile(fileURL, into: store, at: insertionIndex)
                operation.insertionOffsetsBySource[sourceItemID, default: 0] += 1
                if inputID != nil {
                    operation.successfulInputCountsBySource[sourceItemID, default: 0] += 1
                } else {
                    operation.aggregateOutputInserted = true
                }
                operations[operationID] = operation
                if let placeholderID {
                    interaction.removeTransformPlaceholder(placeholderID)
                }
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
        if operation.action == .zip {
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

    private func prepareWorkDirectory() {
        try? FileManager.default.removeItem(at: holding.transformWorkDir)
        try? FileManager.default.createDirectory(
            at: holding.transformWorkDir,
            withIntermediateDirectories: true
        )
    }
}
