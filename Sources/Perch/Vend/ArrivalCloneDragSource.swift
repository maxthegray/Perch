import AppKit
import QuickLookThumbnailing

/// An Option-drag of a recent-arrival ghost: drags out a copy of the original file
/// without bringing it aboard. The ghost row stays a ghost, the original stays where it
/// is, and a drop back onto Perch is refused.
@MainActor
final class ArrivalCloneDragSource: NSObject, NSDraggingSource {
    private let urls: [URL]
    var onEnded: (() -> Void)?

    init(urls: [URL]) {
        precondition(!urls.isEmpty)
        self.urls = urls
        super.init()
    }

    /// Drawn like a shelf item's drag: each file's preview icon under the pointer.
    func beginDrag(from view: NSView, event: NSEvent) {
        let location = view.convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            item.setDraggingFrame(
                NSRect(x: location.x - 24 + offset, y: location.y - 24 - offset, width: 48, height: 48),
                contents: NSWorkspace.shared.icon(forFile: url.path)
            )
            return item
        }
        let session = view.beginDraggingSession(with: items, event: event, source: self)
        NSLog("Perch arrival clone drag started for \(urls.count) file(s)")
        swapInPreviews(for: session)
    }

    /// Ghosts have no cached thumbnail, so the drag starts with file icons and each one
    /// is replaced by its Quick Look preview once generated, matching a shelf item.
    private func swapInPreviews(for session: NSDraggingSession) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for (index, url) in urls.enumerated() {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 48, height: 48),
                scale: scale,
                representationTypes: .thumbnail
            )
            Task { @MainActor [weak session] in
                guard let representation = try? await QLThumbnailGenerator.shared
                    .generateBestRepresentation(for: request),
                    let session else { return }
                let preview = Self.rounded(representation.nsImage)
                var position = 0
                session.enumerateDraggingItems(
                    options: [],
                    for: nil,
                    classes: [NSURL.self],
                    searchOptions: [:]
                ) { item, _, _ in
                    defer { position += 1 }
                    guard position == index else { return }
                    let frame = item.draggingFrame
                    let size = Self.fitted(preview.size, in: frame.size)
                    item.setDraggingFrame(
                        NSRect(
                            x: frame.midX - size.width / 2,
                            y: frame.midY - size.height / 2,
                            width: size.width,
                            height: size.height
                        ),
                        contents: preview
                    )
                }
            }
        }
    }

    private static func fitted(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func rounded(_ image: NSImage) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
            image.draw(in: rect)
            return true
        }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        onEnded?()
    }
}
