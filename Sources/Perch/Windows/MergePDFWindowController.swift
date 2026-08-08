import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers

enum MergePDFReorderPolicy {
    static func move(_ itemIDs: [UUID], itemID: UUID, to proposedIndex: Int) -> [UUID] {
        guard let sourceIndex = itemIDs.firstIndex(of: itemID) else { return itemIDs }
        var reordered = itemIDs
        let moved = reordered.remove(at: sourceIndex)
        var destination = min(max(proposedIndex, 0), itemIDs.count)
        if sourceIndex < destination {
            destination -= 1
        }
        reordered.insert(moved, at: min(max(destination, 0), reordered.count))
        return reordered
    }
}

enum MergePDFPageCountPresentation {
    static func badge(for pageCount: Int?) -> String? {
        guard let pageCount, pageCount > 0 else { return nil }
        return pageCount == 1 ? "1 page" : "\(pageCount) pages"
    }
}

enum MergePDFPreviewPageCounter {
    nonisolated static func pageCount(for fileURLs: [URL]) -> Int? {
        var pageCount = 0
        var containsPDF = false
        for url in fileURLs {
            guard !Task.isCancelled else { return nil }
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .pdf) == true {
                containsPDF = true
                pageCount += PDFDocument(url: url)?.pageCount ?? 0
            } else if type?.conforms(to: .image) == true {
                pageCount += 1
            }
        }
        return containsPDF && pageCount > 0 ? pageCount : nil
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
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 700, height: 510))
        window.minSize = NSSize(width: 520, height: 390)
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
final class MergePDFViewController: NSViewController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate {
    private struct PreviewSource: Sendable {
        let itemID: UUID
        let fileURLs: [URL]
    }

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("MergePDFDocument")
    private static let reorderPasteboardType = NSPasteboard.PasteboardType(
        "com.maximilianreich.perch.merge-pdf-document"
    )

    private let thumbnails = ThumbnailStore()
    private let collectionView = NSCollectionView()
    private let scrollView = NSScrollView()
    private let mergeButton = NSButton(title: "Merge", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var items: [StoredItem] = []
    private var pageCounts: [UUID: Int] = [:]
    private var thumbnailCancellable: AnyCancellable?
    private var pageCountWorker: Task<[UUID: Int], Never>?
    private var pageCountApplyTask: Task<Void, Never>?
    private var previewGeneration = UUID()

    var onMerge: (([StoredItem]) -> Void)?
    var onCancel: (() -> Void)?

    var reorderView: NSView { collectionView }
    var mergeDefaultButtonCell: NSButtonCell? { mergeButton.cell as? NSButtonCell }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        thumbnailCancellable = thumbnails.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.reloadCollection()
            }
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

        let heading = NSTextField(labelWithString: "Arrange documents in page order")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        let detail = NSTextField(
            wrappingLabelWithString: "Drag tiles to reorder them. Each PDF stays together as one document."
        )
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 12)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 148, height: 184)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14
        layout.sectionInset = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            MergePDFCollectionItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )
        collectionView.registerForDraggedTypes([Self.reorderPasteboardType])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

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

        let buttons = NSStackView(views: [cancelButton, mergeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        for subview in [heading, detail, scrollView, buttons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),

            detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),

            scrollView.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),

            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
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
        reloadCollection()
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
            reloadCollection()
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let collectionItem = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        ) as! MergePDFCollectionItem
        let item = items[indexPath.item]
        let thumbnail = thumbnails.thumbnail(for: item, pointSize: 112) ?? item.iconImage()
        collectionItem.configure(
            image: thumbnail,
            title: item.metadata.title,
            pageCountBadge: MergePDFPageCountPresentation.badge(for: pageCounts[item.id])
        )
        return collectionItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard items.indices.contains(indexPath.item) else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            items[indexPath.item].id.uuidString,
            forType: Self.reorderPasteboardType
        )
        return pasteboardItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard draggingInfo.draggingPasteboard.string(forType: Self.reorderPasteboardType) != nil
        else { return [] }
        proposedDropOperation.pointee = .before
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let rawID = draggingInfo.draggingPasteboard.string(
            forType: Self.reorderPasteboardType
        ), let itemID = UUID(uuidString: rawID) else { return false }
        let reorderedIDs = MergePDFReorderPolicy.move(
            items.map(\.id),
            itemID: itemID,
            to: indexPath.item
        )
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        items = reorderedIDs.compactMap { itemsByID[$0] }
        reloadCollection()
        return true
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
            self.reloadCollection()
        }
    }

    private func reloadCollection() {
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        updateCollectionFrame()
    }

    private func updateCollectionFrame() {
        guard isViewLoaded else { return }
        let viewport = scrollView.contentSize
        guard viewport.width > 0, viewport.height > 0 else { return }
        if abs(collectionView.frame.width - viewport.width) > 0.5 {
            collectionView.setFrameSize(NSSize(
                width: viewport.width,
                height: max(collectionView.frame.height, viewport.height)
            ))
            collectionView.collectionViewLayout?.invalidateLayout()
        }
        collectionView.layoutSubtreeIfNeeded()
        let content = collectionView.collectionViewLayout?.collectionViewContentSize ?? .zero
        collectionView.setFrameSize(NSSize(
            width: viewport.width,
            height: max(viewport.height, content.height)
        ))
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

private final class MergePDFCollectionItem: NSCollectionViewItem {
    private let previewImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let badgeField = NSTextField(labelWithString: "")

    override func loadView() {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 12
        tile.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = NSColor.separatorColor.cgColor

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(previewImageView)

        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: 11, weight: .medium)
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.maximumNumberOfLines = 2
        titleField.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(titleField)

        badgeField.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeField.textColor = .secondaryLabelColor
        badgeField.alignment = .center
        badgeField.wantsLayer = true
        badgeField.layer?.cornerRadius = 7
        badgeField.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.9).cgColor
        badgeField.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(badgeField)

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: tile.topAnchor, constant: 12),
            previewImageView.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 12),
            previewImageView.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -12),
            previewImageView.heightAnchor.constraint(equalToConstant: 116),

            titleField.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -8),
            titleField.bottomAnchor.constraint(lessThanOrEqualTo: tile.bottomAnchor, constant: -8),

            badgeField.topAnchor.constraint(equalTo: tile.topAnchor, constant: 8),
            badgeField.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -8),
            badgeField.heightAnchor.constraint(equalToConstant: 18),
            badgeField.widthAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])

        view = tile
    }

    func configure(image: NSImage, title: String, pageCountBadge: String?) {
        previewImageView.image = image
        titleField.stringValue = title
        badgeField.stringValue = pageCountBadge ?? ""
        badgeField.isHidden = pageCountBadge == nil
    }
}
