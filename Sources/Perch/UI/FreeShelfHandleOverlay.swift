import AppKit

/// Window controls for a cursor-summoned shelf, layered over the top grip strip of the
/// card. The strip drags the panel and its trailing close button dismisses it. Hidden
/// (and inert) in edge mode.
final class FreeShelfHandleOverlay: NSView {
    var onDismiss: (() -> Void)?

    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureCloseButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCloseButton()
    }

    private func configureCloseButton() {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(configuration)
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.isBordered = false
        closeButton.refusesFirstResponder = true
        closeButton.toolTip = "Close summoned shelf"
        closeButton.target = self
        closeButton.action = #selector(dismissShelf)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalTo: heightAnchor)
        ])
    }

    @objc private func dismissShelf() {
        onDismiss?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        // Native borderless-window drag — moves the panel with the cursor.
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        addCursorRect(closeButton.frame, cursor: .pointingHand)
    }
}
