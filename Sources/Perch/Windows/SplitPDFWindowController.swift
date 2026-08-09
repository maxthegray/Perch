import AppKit
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class SplitPDFWindowController: NSObject, NSWindowDelegate {
    private let viewController = SplitPDFViewController()
    private var window: NSWindow?
    private var item: StoredItem?
    private var onConfirm: ((StoredItem, PDFSplitPlan) -> Void)?

    override init() {
        super.init()
        viewController.onSplit = { [weak self] plan in
            self?.complete(with: plan)
        }
        viewController.onCancel = { [weak self] in
            self?.cancel()
        }
    }

    func show(
        item: StoredItem,
        onConfirm: @escaping (StoredItem, PDFSplitPlan) -> Void
    ) {
        guard viewController.setItem(item) else { return }
        self.item = item
        self.onConfirm = onConfirm

        let window = window ?? makeWindow()
        let pageCount = viewController.pageCount
        let fittedHeight = min(620, max(320, 122 + CGFloat(pageCount) * 84
            + CGFloat(max(0, pageCount - 1)) * 12))
        window.setContentSize(NSSize(width: 390, height: fittedHeight))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        item = nil
        onConfirm = nil
        viewController.reset()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: viewController)
        window.title = "Split PDF"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 390, height: 520))
        window.minSize = NSSize(width: 340, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.defaultButtonCell = viewController.splitDefaultButtonCell
        window.center()
        self.window = window
        return window
    }

    private func complete(with plan: PDFSplitPlan) {
        guard let item else { return }
        let confirmation = onConfirm
        self.item = nil
        onConfirm = nil
        window?.orderOut(nil)
        viewController.reset()
        confirmation?(item, plan)
    }

    private func cancel() {
        item = nil
        onConfirm = nil
        window?.orderOut(nil)
        viewController.reset()
    }
}

@MainActor
final class SplitPDFViewController: NSViewController {
    private let pagesView = SplitPDFPagesView()
    private let scrollView = NSScrollView()
    private let summaryField = NSTextField(labelWithString: "")
    private let splitButton = NSButton(title: "Split", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var breaksAfterPages: Set<Int> = []

    var onSplit: ((PDFSplitPlan) -> Void)?
    var onCancel: (() -> Void)?

    var pageCount: Int { pagesView.pageCount }
    var splitDefaultButtonCell: NSButtonCell? { splitButton.cell as? NSButtonCell }
    var pageArrangementView: SplitPDFPagesView { pagesView }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        pagesView.onBreaksChange = { [weak self] breaks in
            self?.breaksAfterPages = breaks
            self?.updateSummary()
            self?.updatePagesFrame()
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

        let heading = NSTextField(labelWithString: "Choose where to split")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)

        scrollView.documentView = pagesView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        summaryField.font = .systemFont(ofSize: 11, weight: .medium)
        summaryField.textColor = .secondaryLabelColor

        splitButton.bezelStyle = .rounded
        splitButton.keyEquivalent = "\r"
        splitButton.keyEquivalentModifierMask = []
        splitButton.target = self
        splitButton.action = #selector(splitAction(_:))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []
        cancelButton.target = self
        cancelButton.action = #selector(cancelAction(_:))

        let footerSpacer = NSView()
        let footer = NSStackView(views: [summaryField, footerSpacer, cancelButton, splitButton])
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.alignment = .centerY
        summaryField.setContentHuggingPriority(.required, for: .horizontal)
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        splitButton.setContentHuggingPriority(.required, for: .horizontal)

        for subview in [heading, scrollView, footer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),

            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])

        view = root
        updateSummary()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePagesFrame()
    }

    @discardableResult
    func setItem(_ item: StoredItem) -> Bool {
        loadViewIfNeeded()
        guard let url = item.backingFileURLs().first(where: { url in
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                ?? UTType(filenameExtension: url.pathExtension)
            return type?.conforms(to: .pdf) == true
        }), let document = PDFDocument(url: url), document.pageCount > 1 else {
            reset()
            return false
        }

        breaksAfterPages = []
        let entries = (0..<document.pageCount).compactMap { index -> SplitPDFPageEntry? in
            guard let page = document.page(at: index) else { return nil }
            return SplitPDFPageEntry(
                pageNumber: index + 1,
                image: page.thumbnail(
                    of: NSSize(width: 72, height: 88),
                    for: .mediaBox
                )
            )
        }
        guard entries.count == document.pageCount else {
            reset()
            return false
        }
        pagesView.configure(entries, breaksAfterPages: [])
        updateSummary()
        updatePagesFrame()
        return true
    }

    func reset() {
        breaksAfterPages = []
        if isViewLoaded {
            pagesView.configure([], breaksAfterPages: [])
            updateSummary()
            updatePagesFrame()
        }
    }

    private func updateSummary() {
        let count = breaksAfterPages.count + 1
        summaryField.stringValue = count == 1 ? "1 PDF" : "\(count) PDFs"
        splitButton.isEnabled = !breaksAfterPages.isEmpty
    }

    private func updatePagesFrame() {
        guard isViewLoaded else { return }
        let viewport = scrollView.contentSize
        guard viewport.width > 0, viewport.height > 0 else { return }
        pagesView.setFrameSize(NSSize(
            width: viewport.width,
            height: max(viewport.height, pagesView.requiredHeight)
        ))
        pagesView.needsLayout = true
        pagesView.layoutSubtreeIfNeeded()
    }

    @objc private func splitAction(_ sender: NSButton) {
        guard !breaksAfterPages.isEmpty else { return }
        onSplit?(PDFSplitPlan(breaksAfterPages: Array(breaksAfterPages)))
    }

    @objc private func cancelAction(_ sender: NSButton) {
        onCancel?()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

struct SplitPDFPageEntry {
    let pageNumber: Int
    let image: NSImage
}

@MainActor
final class SplitPDFPagesView: NSView {
    private static let rowHeight: CGFloat = 84
    private static let restingGap: CGFloat = 12
    private static let splitGap: CGFloat = 34
    private static let contentInset: CGFloat = 2

    private var entries: [SplitPDFPageEntry] = []
    private var rows: [Int: SplitPDFPageRowView] = [:]
    private var dividers: [Int: SplitPDFDividerView] = [:]
    private var breaksAfterPages: Set<Int> = []

    var onBreaksChange: ((Set<Int>) -> Void)?
    var pageCount: Int { entries.count }
    var selectedBreaks: Set<Int> { breaksAfterPages }
    var requiredHeight: CGFloat {
        let rowsHeight = CGFloat(entries.count) * Self.rowHeight
        guard entries.count > 1 else { return Self.contentInset * 2 + rowsHeight }
        let gapsHeight = (1..<entries.count).reduce(CGFloat.zero) { height, page in
            height + (breaksAfterPages.contains(page) ? Self.splitGap : Self.restingGap)
        }
        return Self.contentInset * 2 + rowsHeight + gapsHeight
    }

    override var isFlipped: Bool { true }

    func configure(_ entries: [SplitPDFPageEntry], breaksAfterPages: Set<Int>) {
        for row in rows.values { row.removeFromSuperview() }
        for divider in dividers.values { divider.removeFromSuperview() }
        rows = [:]
        dividers = [:]
        self.entries = entries
        self.breaksAfterPages = Set(breaksAfterPages.filter {
            $0 > 0 && $0 < entries.count
        })

        for entry in entries {
            let row = SplitPDFPageRowView()
            row.configure(entry)
            addSubview(row)
            rows[entry.pageNumber] = row

            guard entry.pageNumber < entries.count else { continue }
            let divider = SplitPDFDividerView(breakAfterPage: entry.pageNumber)
            divider.onToggle = { [weak self] page in
                self?.toggleBreak(after: page)
            }
            addSubview(divider)
            dividers[entry.pageNumber] = divider
        }
        needsLayout = true
    }

    func toggleBreak(after page: Int) {
        guard page > 0, page < entries.count else { return }
        if breaksAfterPages.contains(page) {
            breaksAfterPages.remove(page)
        } else {
            breaksAfterPages.insert(page)
        }
        layoutPages(animated: true)
        onBreaksChange?(breaksAfterPages)
    }

    override func layout() {
        super.layout()
        layoutPages(animated: false)
    }

    private func layoutPages(animated: Bool) {
        let orderedBreaks = breaksAfterPages.sorted()
        var frames: [(NSView, NSRect)] = []
        var y = Self.contentInset
        for entry in entries {
            if let row = rows[entry.pageNumber] {
                frames.append((row, NSRect(
                    x: Self.contentInset,
                    y: y,
                    width: max(1, bounds.width - Self.contentInset * 2),
                    height: Self.rowHeight
                )))
            }
            y += Self.rowHeight

            guard let divider = dividers[entry.pageNumber] else { continue }
            let isSplit = breaksAfterPages.contains(entry.pageNumber)
            let gap = isSplit ? Self.splitGap : Self.restingGap
            let groupNumber = orderedBreaks.firstIndex(of: entry.pageNumber).map { $0 + 2 }
            divider.configure(isSplit: isSplit, groupNumber: groupNumber)
            frames.append((divider, NSRect(
                x: Self.contentInset,
                y: y,
                width: max(1, bounds.width - Self.contentInset * 2),
                height: gap
            )))
            y += gap
        }

        let applyFrames = {
            for (view, frame) in frames {
                view.frame = frame
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

private final class SplitPDFPageRowView: NSView {
    private let pageNumberField = NSTextField(labelWithString: "")
    private let previewImageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func buildView() {
        pageNumberField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        pageNumberField.textColor = .tertiaryLabelColor
        pageNumberField.alignment = .right
        pageNumberField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pageNumberField)

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 3
        previewImageView.layer?.masksToBounds = true
        previewImageView.layer?.borderWidth = 0.5
        previewImageView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewImageView)

        NSLayoutConstraint.activate([
            pageNumberField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pageNumberField.centerYAnchor.constraint(equalTo: centerYAnchor),
            pageNumberField.widthAnchor.constraint(equalToConstant: 28),

            previewImageView.leadingAnchor.constraint(equalTo: pageNumberField.trailingAnchor, constant: 14),
            previewImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewImageView.widthAnchor.constraint(equalToConstant: 56),
            previewImageView.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    func configure(_ entry: SplitPDFPageEntry) {
        pageNumberField.stringValue = "\(entry.pageNumber)"
        previewImageView.image = entry.image
        setAccessibilityElement(true)
        setAccessibilityLabel("Page \(entry.pageNumber)")
    }
}

private final class SplitPDFDividerView: NSView {
    let breakAfterPage: Int
    private var isSplit = false
    private var groupNumber: Int?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    var onToggle: ((Int) -> Void)?

    init(breakAfterPage: Int) {
        self.breakAfterPage = breakAfterPage
        super.init(frame: .zero)
        toolTip = "Split after page \(breakAfterPage)"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Split after page \(breakAfterPage)")
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(isSplit: Bool, groupNumber: Int?) {
        self.isSplit = isSplit
        self.groupNumber = groupNumber
        setAccessibilityValue(isSplit ? "On" : "Off")
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
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
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?(breakAfterPage)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSplit || isHovered else { return }
        let color = NSColor.controlAccentColor
        let line = NSBezierPath()
        let centerY = bounds.midY
        var lineStart: CGFloat = 52

        if isSplit, let groupNumber {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let label = NSAttributedString(string: "PDF \(groupNumber)", attributes: attributes)
            label.draw(at: NSPoint(x: 8, y: centerY - label.size().height / 2))
            lineStart = 58
        }

        line.move(to: NSPoint(x: lineStart, y: centerY))
        line.line(to: NSPoint(x: max(lineStart, bounds.maxX - 10), y: centerY))
        line.lineWidth = isSplit ? 1.25 : 0.75
        color.setStroke()
        line.stroke()
    }
}
