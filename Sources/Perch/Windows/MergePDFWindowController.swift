import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers

enum MergePDFReorderPolicy {
    static func move(_ itemIDs: [UUID], itemID: UUID, to proposedIndex: Int) -> [UUID] {
        guard let sourceIndex = itemIDs.firstIndex(of: itemID) else { return itemIDs }
        var reordered = itemIDs
        let moved = reordered.remove(at: sourceIndex)
        let destination = min(max(proposedIndex, 0), reordered.count)
        reordered.insert(moved, at: destination)
        return reordered
    }
}

enum MergePDFPreviewPageCounter {
    nonisolated static func pageCount(for fileURLs: [URL]) -> Int? {
        var pageCount = 0
        for url in fileURLs {
            guard !Task.isCancelled else { return nil }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .pdf) == true {
                pageCount += PDFDocument(url: url)?.pageCount ?? 0
            } else if type?.conforms(to: .image) == true {
                pageCount += 1
            }
        }
        return pageCount > 0 ? pageCount : nil
    }
}

@MainActor
final class MergePDFWindowController: NSObject, NSWindowDelegate {
    private let viewController = MergePDFViewController()
    private var window: NSWindow?
    private var onConfirm: (([StoredItem]) -> Void)?

    override init() {
        super.init()
        viewController.onMerge = { [weak self] items in
            self?.complete(with: items)
        }
        viewController.onCancel = { [weak self] in
            self?.cancel()
        }
    }

    func show(items: [StoredItem], onConfirm: @escaping ([StoredItem]) -> Void) {
        guard items.count >= 2 else { return }
        self.onConfirm = onConfirm
        viewController.setItems(items)

        let window = window ?? makeWindow()
        let fittedHeight = min(480, max(280, 118 + CGFloat(items.count) * 70))
        window.setContentSize(NSSize(
            width: max(window.contentLayoutRect.width, 470),
            height: fittedHeight
        ))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(viewController.reorderView)
    }

    func windowWillClose(_ notification: Notification) {
        onConfirm = nil
        viewController.reset()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: viewController)
        window.title = "Merge to PDF"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 470, height: 540))
        window.minSize = NSSize(width: 410, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.defaultButtonCell = viewController.mergeDefaultButtonCell
        window.center()
        self.window = window
        return window
    }

    private func complete(with items: [StoredItem]) {
        let confirmation = onConfirm
        onConfirm = nil
        window?.orderOut(nil)
        viewController.reset()
        confirmation?(items)
    }

    private func cancel() {
        onConfirm = nil
        window?.orderOut(nil)
        viewController.reset()
    }
}

@MainActor
final class MergePDFViewController: NSViewController {
    private struct PreviewSource: Sendable {
        let itemID: UUID
        let fileURLs: [URL]
    }

    private let thumbnails = ThumbnailStore()
    private let arrangementView = MergePDFReorderView()
    private let scrollView = NSScrollView()
    private let summaryField = NSTextField(labelWithString: "")
    private let mergeButton = NSButton(title: "Merge PDF", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var items: [StoredItem] = []
    private var pageCounts: [UUID: Int] = [:]
    private var thumbnailCancellable: AnyCancellable?
    private var pageCountWorker: Task<[UUID: Int], Never>?
    private var pageCountApplyTask: Task<Void, Never>?
    private var previewGeneration = UUID()

    var onMerge: (([StoredItem]) -> Void)?
    var onCancel: (() -> Void)?

    var reorderView: NSView { arrangementView }
    var mergeDefaultButtonCell: NSButtonCell? { mergeButton.cell as? NSButtonCell }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        thumbnailCancellable = thumbnails.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.reloadArrangement()
            }
        }
        arrangementView.onOrderChange = { [weak self] orderedIDs in
            guard let self else { return }
            let itemsByID = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, $0) })
            self.items = orderedIDs.compactMap { itemsByID[$0] }
        }
    }

    convenience init() {
        self.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let heading = NSTextField(labelWithString: "Put these in order")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)

        scrollView.documentView = arrangementView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        summaryField.font = .systemFont(ofSize: 11, weight: .medium)
        summaryField.textColor = .secondaryLabelColor

        mergeButton.bezelStyle = .rounded
        mergeButton.keyEquivalent = "\r"
        mergeButton.keyEquivalentModifierMask = []
        mergeButton.target = self
        mergeButton.action = #selector(mergeAction(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))

        let footerSpacer = NSView()
        let footer = NSStackView(views: [summaryField, footerSpacer, cancelButton, mergeButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        summaryField.setContentHuggingPriority(.required, for: .horizontal)
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        mergeButton.setContentHuggingPriority(.required, for: .horizontal)

        for subview in [heading, scrollView, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),

            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCollectionFrame()
    }

    func setItems(_ items: [StoredItem]) {
        loadViewIfNeeded()
        self.items = items
        pageCounts = [:]
        reloadArrangement()
        requestPageCounts()
    }

    func reset() {
        pageCountWorker?.cancel()
        pageCountApplyTask?.cancel()
        pageCountWorker = nil
        pageCountApplyTask = nil
        previewGeneration = UUID()
        items = []
        pageCounts = [:]
        if isViewLoaded {
            reloadArrangement()
        }
    }

    private func requestPageCounts() {
        pageCountWorker?.cancel()
        pageCountApplyTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        let sources = items.map { item in
            PreviewSource(
                itemID: item.id,
                fileURLs: item.backingFileURLs()
            )
        }
        let worker = Task.detached(priority: .userInitiated) {
            var counts: [UUID: Int] = [:]
            for source in sources {
                guard !Task.isCancelled else { return counts }
                if let pageCount = MergePDFPreviewPageCounter.pageCount(
                    for: source.fileURLs
                ) {
                    counts[source.itemID] = pageCount
                }
            }
            return counts
        }
        pageCountWorker = worker
        pageCountApplyTask = Task { @MainActor [weak self] in
            let counts = await worker.value
            guard let self,
                  !Task.isCancelled,
                  self.previewGeneration == generation else { return }
            self.pageCounts = counts
            self.reloadArrangement()
        }
    }

    private func reloadArrangement() {
        updateSummary()
        arrangementView.configure(items.map { item in
            MergePDFReorderEntry(
                id: item.id,
                image: thumbnails.thumbnail(for: item, pointSize: 56) ?? item.iconImage(),
                title: item.metadata.title
            )
        })
        updateCollectionFrame()
    }

    private func updateSummary() {
        let itemLabel = items.count == 1 ? "1 item" : "\(items.count) items"
        guard items.count == pageCounts.count else {
            summaryField.stringValue = itemLabel
            return
        }
        let totalPages = pageCounts.values.reduce(0, +)
        let pageLabel = totalPages == 1 ? "1 page" : "\(totalPages) pages"
        summaryField.stringValue = "\(itemLabel) · \(pageLabel)"
    }

    private func updateCollectionFrame() {
        guard isViewLoaded else { return }
        let viewport = scrollView.contentSize
        guard viewport.width > 0, viewport.height > 0 else { return }
        arrangementView.setFrameSize(NSSize(
            width: viewport.width,
            height: max(viewport.height, arrangementView.requiredHeight)
        ))
        arrangementView.needsLayout = true
        arrangementView.layoutSubtreeIfNeeded()
    }

    @objc private func mergeAction(_ sender: NSButton) {
        guard items.count >= 2 else { return }
        onMerge?(items)
    }

    @objc private func cancelAction(_ sender: NSButton) {
        onCancel?()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

struct MergePDFReorderEntry {
    let id: UUID
    let image: NSImage
    let title: String
}

@MainActor
final class MergePDFReorderView: NSView {
    private static let rowHeight: CGFloat = 64
    private static let rowSpacing: CGFloat = 6
    private static let contentInset: CGFloat = 3

    private var orderedIDs: [UUID] = []
    private var rows: [UUID: MergePDFReorderRowView] = [:]
    private var draggedID: UUID?
    private var dragOffsetY: CGFloat = 0

    var onOrderChange: (([UUID]) -> Void)?
    var itemCount: Int { orderedIDs.count }
    var orderedItemIDs: [UUID] { orderedIDs }
    var requiredHeight: CGFloat {
        let gaps = CGFloat(max(0, orderedIDs.count - 1)) * Self.rowSpacing
        return Self.contentInset * 2 + CGFloat(orderedIDs.count) * Self.rowHeight + gaps
    }

    override var isFlipped: Bool { true }

    func configure(_ entries: [MergePDFReorderEntry]) {
        let entryIDs = entries.map(\.id)
        let staleIDs = Set(rows.keys).subtracting(entryIDs)
        for id in staleIDs {
            rows.removeValue(forKey: id)?.removeFromSuperview()
        }

        for entry in entries {
            let row = rows[entry.id] ?? makeRow(for: entry.id)
            row.configure(image: entry.image, title: entry.title)
            rows[entry.id] = row
        }
        orderedIDs = entryIDs
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutRows(animated: false)
    }

    func moveItem(_ itemID: UUID, to index: Int, animated: Bool) {
        let reordered = MergePDFReorderPolicy.move(orderedIDs, itemID: itemID, to: index)
        guard reordered != orderedIDs else { return }
        orderedIDs = reordered
        layoutRows(animated: animated)
        onOrderChange?(orderedIDs)
    }

    private func makeRow(for id: UUID) -> MergePDFReorderRowView {
        let row = MergePDFReorderRowView(itemID: id)
        row.onDragBegan = { [weak self] itemID, event in
            self?.beginDragging(itemID, event: event)
        }
        row.onDragChanged = { [weak self] itemID, event in
            self?.updateDragging(itemID, event: event)
        }
        row.onDragEnded = { [weak self] itemID in
            self?.endDragging(itemID)
        }
        addSubview(row)
        return row
    }

    private func beginDragging(_ itemID: UUID, event: NSEvent) {
        guard draggedID == nil, let row = rows[itemID] else { return }
        draggedID = itemID
        let point = convert(event.locationInWindow, from: nil)
        dragOffsetY = point.y - row.frame.minY
        row.setDragging(true)
    }

    private func updateDragging(_ itemID: UUID, event: NSEvent) {
        guard draggedID == itemID, let row = rows[itemID] else { return }
        _ = autoscroll(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let maximumY = max(Self.contentInset, bounds.height - Self.contentInset - Self.rowHeight)
        let rowY = min(max(point.y - dragOffsetY, Self.contentInset), maximumY)
        row.frame.origin.y = rowY

        let firstCenter = Self.contentInset + Self.rowHeight / 2
        let stride = Self.rowHeight + Self.rowSpacing
        let rawIndex = ((row.frame.midY - firstCenter) / stride).rounded()
        let targetIndex = min(max(Int(rawIndex), 0), max(0, orderedIDs.count - 1))
        moveItem(itemID, to: targetIndex, animated: true)
    }

    private func endDragging(_ itemID: UUID) {
        guard draggedID == itemID, let row = rows[itemID] else { return }
        draggedID = nil
        layoutRows(animated: true)
        row.setDragging(false)
    }

    private func layoutRows(animated: Bool) {
        let frames = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().compactMap {
            index, id -> (UUID, NSRect)? in
            guard rows[id] != nil else { return nil }
            let y = Self.contentInset + CGFloat(index) * (Self.rowHeight + Self.rowSpacing)
            return (id, NSRect(
                x: Self.contentInset,
                y: y,
                width: max(1, bounds.width - Self.contentInset * 2),
                height: Self.rowHeight
            ))
        })

        let applyFrames = {
            for (index, id) in self.orderedIDs.enumerated() {
                guard let row = self.rows[id] else { continue }
                row.setOrder(index + 1)
                if id != self.draggedID, let frame = frames[id] {
                    row.frame = frame
                }
            }
        }

        guard animated else {
            applyFrames()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            applyFrames()
        }
    }
}

private final class MergePDFReorderRowView: NSView {
    let itemID: UUID
    private let orderField = NSTextField(labelWithString: "")
    private let previewImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var cursorIsPushed = false

    var onDragBegan: ((UUID, NSEvent) -> Void)?
    var onDragChanged: ((UUID, NSEvent) -> Void)?
    var onDragEnded: ((UUID) -> Void)?

    init(itemID: UUID) {
        self.itemID = itemID
        super.init(frame: .zero)
        buildView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func buildView() {
        wantsLayer = true
        layer?.cornerRadius = 8
        updateBackground()

        orderField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        orderField.textColor = .tertiaryLabelColor
        orderField.alignment = .right
        orderField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(orderField)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 4
        previewImageView.layer?.masksToBounds = true
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewImageView)

        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.maximumNumberOfLines = 1
        titleField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleField)

        NSLayoutConstraint.activate([
            orderField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            orderField.centerYAnchor.constraint(equalTo: centerYAnchor),
            orderField.widthAnchor.constraint(equalToConstant: 25),

            previewImageView.leadingAnchor.constraint(equalTo: orderField.trailingAnchor, constant: 10),
            previewImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 36),
            previewImageView.heightAnchor.constraint(equalToConstant: 48),

            titleField.leadingAnchor.constraint(equalTo: previewImageView.trailingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        toolTip = "Drag to reorder"
        setAccessibilityElement(true)
        setAccessibilityHelp("Drag to reorder")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackground()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        cursorIsPushed = true
        onDragBegan?(itemID, event)
    }

    override func mouseDragged(with event: NSEvent) {
        onDragChanged?(itemID, event)
    }

    override func mouseUp(with event: NSEvent) {
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
        onDragEnded?(itemID)
    }

    func configure(image: NSImage, title: String) {
        previewImageView.image = image
        titleField.stringValue = title
        setAccessibilityLabel(title)
    }

    func setOrder(_ order: Int) {
        orderField.stringValue = String(format: "%02d", order)
        setAccessibilityLabel("\(order). \(titleField.stringValue)")
    }

    func setDragging(_ dragging: Bool) {
        layer?.zPosition = dragging ? 10 : 0
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dragging ? 0.22 : 0
        layer?.shadowRadius = dragging ? 9 : 0
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        updateBackground(dragging: dragging)
    }

    private func updateBackground(dragging: Bool = false) {
        let color: NSColor
        if dragging {
            color = .controlBackgroundColor
        } else if isHovered {
            color = NSColor.labelColor.withAlphaComponent(0.055)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }
}
