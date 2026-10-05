import AppKit

/// Shows the system share sheet (AirDrop, Messages, Mail, …) for shelf items, anchored
/// to the shelf itself: the standard share menu item anchors to the context menu, which
/// has closed by the time the sheet finishes loading, so it never appears.
/// The shelf panel never becomes key, so Perch activates once a service is chosen —
/// otherwise the compose sheets can't take typing — and hands focus back afterwards.
@MainActor
final class ShelfSharing: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private var picker: NSSharingServicePicker?
    private var previousApp: NSRunningApplication?

    func canShare(_ item: StoredItem) -> Bool {
        !Self.shareItems(for: item).isEmpty
    }

    func show(_ items: [StoredItem], relativeTo rect: NSRect, of view: NSView) {
        let shareItems = items.flatMap(Self.shareItems(for:))
        guard !shareItems.isEmpty else { return }
        let picker = NSSharingServicePicker(items: shareItems)
        picker.delegate = self
        self.picker = picker
        picker.show(relativeTo: rect, of: view, preferredEdge: .maxX)
    }

    static func shareItems(for item: StoredItem) -> [Any] {
        let fileURLs = item.backingFileURLs()
        if !fileURLs.isEmpty { return fileURLs }
        if let data = item.data(forType: .URL),
           let string = String(data: data, encoding: .utf8),
           let url = URL(string: string), url.scheme != nil {
            return [url]
        }
        if let data = item.data(forType: .string),
           let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return [text]
        }
        return []
    }

    // MARK: NSSharingServicePickerDelegate

    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        delegateFor sharingService: NSSharingService
    ) -> NSSharingServiceDelegate? {
        self
    }

    nonisolated func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        MainActor.assumeIsolated {
            picker = nil
            guard service != nil else { return }
            if let frontmost = NSWorkspace.shared.frontmostApplication,
               frontmost != NSRunningApplication.current {
                previousApp = frontmost
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: NSSharingServiceDelegate

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { restoreFocus() }
    }

    nonisolated func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: Error
    ) {
        MainActor.assumeIsolated { restoreFocus() }
    }

    private func restoreFocus() {
        previousApp?.activate()
        previousApp = nil
    }
}
