import AppKit
import Quartz

/// Presents shelf items in the system Quick Look panel. The shelf panel never becomes
/// key, so Perch activates for the duration of the preview (letting Space, Esc and the
/// arrow keys reach the panel) and hands focus back to the previous app on close.
@MainActor
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var entries: [(url: URL, item: StoredItem)] = []
    private var sourceFrame: ((StoredItem) -> NSRect?)?
    private var previousApp: NSRunningApplication?

    static let scratchDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PerchQuickLook", isDirectory: true)

    func canPreview(_ item: StoredItem) -> Bool {
        !item.metadata.backingFileNames.isEmpty || Self.clippingText(for: item) != nil
    }

    func show(_ items: [StoredItem], sourceFrame: @escaping (StoredItem) -> NSRect?) {
        try? FileManager.default.removeItem(at: Self.scratchDirectory)
        let entries = items.flatMap { item in
            Self.previewURLs(for: item, scratchDirectory: Self.scratchDirectory).map { (url: $0, item: item) }
        }
        guard !entries.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.entries = entries
        self.sourceFrame = sourceFrame

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost != NSRunningApplication.current {
            previousApp = frontmost
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    static func previewURLs(for item: StoredItem, scratchDirectory: URL) -> [URL] {
        let fileURLs = item.backingFileURLs()
        if !fileURLs.isEmpty { return fileURLs }
        guard let text = clippingText(for: item) else { return [] }
        let url = scratchDirectory.appendingPathComponent("\(item.id.uuidString).txt")
        do {
            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        } catch {
            return []
        }
        return [url]
    }

    private static func clippingText(for item: StoredItem) -> String? {
        for type in [NSPasteboard.PasteboardType.string, .URL] {
            if let data = item.data(forType: type),
               let text = String(data: data, encoding: .utf8),
               !text.isEmpty {
                return text
            }
        }
        return nil
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { entries.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated {
            entries.indices.contains(index) ? entries[index].url as NSURL : nil
        }
    }

    // MARK: QLPreviewPanelDelegate

    nonisolated func previewPanel(
        _ panel: QLPreviewPanel!,
        sourceFrameOnScreenFor item: QLPreviewItem!
    ) -> NSRect {
        MainActor.assumeIsolated {
            guard let url = item.previewItemURL,
                  let entry = entries.first(where: { $0.url == url })
            else { return .zero }
            return sourceFrame?(entry.item) ?? .zero
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            entries = []
            sourceFrame = nil
            previousApp?.activate()
            previousApp = nil
        }
    }
}
