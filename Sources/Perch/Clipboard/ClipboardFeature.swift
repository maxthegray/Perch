import AppKit
import ClipboardCore
import ImageIO
import UniformTypeIdentifiers

/// Everything clipboard history does, behind one optional reference, like
/// `SmartPerchFeature`: while the switch is off this is never built, so nothing polls the
/// pasteboard, no database is opened and no hotkey is held.
@MainActor
final class ClipboardFeature {
    private let store: ClipStore
    private let pasteboard: NSPasteboard
    private let watcher: PasteboardWatcher
    private let panelModel = ClipboardPanelModel()
    private lazy var panel = ClipboardPanelController(model: panelModel)
    private var hotKey: GlobalHotKey?
    private let queue = DispatchQueue(label: "com.maximilianreich.perch.clipboard", qos: .utility)

    init?(databaseURL: URL, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        watcher = PasteboardWatcher(pasteboard: pasteboard)
        do {
            store = try ClipStore(databaseURL: databaseURL)
        } catch {
            NSLog("Perch could not open the clipboard history: \(error)")
            return nil
        }

        panelModel.onChoose = { [weak self] clip in self?.restore(clip) }
        panelModel.onDelete = { [weak self] clip in self?.delete(clip) }
        watcher.onCopy = { [weak self] items, source in self?.record(items, source: source) }
        refresh()
        watcher.start()
    }

    /// Returns false when macOS refuses the shortcut.
    @discardableResult
    func registerHotKey(_ combo: KeyCombo) -> Bool {
        hotKey?.invalidate()
        hotKey = GlobalHotKey(combo: combo) { [weak self] in
            MainActor.assumeIsolated {
                self?.watcher.poll()
                self?.panel.toggle()
            }
        }
        return hotKey != nil
    }

    func unregisterHotKey() {
        hotKey?.invalidate()
        hotKey = nil
    }

    func clearHistory() throws {
        try queue.sync { try store.deleteAll() }
        refresh()
    }

    func shutDown() {
        watcher.stop()
        unregisterHotKey()
        panel.hide()
        queue.sync {}
    }

    private func record(_ items: [ClipPasteboardItem], source: String?) {
        let store = store
        queue.async { [weak self] in
            guard var capture = ClipCapturePolicy.capture(items) else { return }
            if capture.kind == .image {
                let image = Self.imageData(in: capture.representations)
                capture.thumbnail = image.flatMap(Self.thumbnail(for:))
                if let size = image.flatMap(Self.pixelSize(of:)) {
                    capture.title = "Image \(size.width)×\(size.height)"
                }
            }
            do {
                try store.record(capture, sourceBundleID: source, at: Date())
            } catch {
                NSLog("Perch could not save a clip: \(error)")
                return
            }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func refresh() {
        let clips = queue.sync { try? store.recent() }
        panelModel.update(clips: clips ?? [])
    }

    private func restore(_ clip: ClipSummary) {
        let representations = queue.sync { try? store.representations(for: clip.id) } ?? []
        guard !representations.isEmpty else { return }

        var items: [Int: NSPasteboardItem] = [:]
        for representation in representations {
            let item = items[representation.itemIndex] ?? NSPasteboardItem()
            item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
            items[representation.itemIndex] = item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items.keys.sorted().compactMap { items[$0] })
        watcher.noteOwnWrite()
        panel.hide()
    }

    private func delete(_ clip: ClipSummary) {
        queue.sync { try? store.delete(id: clip.id) }
        refresh()
    }

    nonisolated private static func imageData(in representations: [ClipRepresentation]) -> Data? {
        ClipCapturePolicy.imageTypes.lazy.compactMap { type in
            representations.first { $0.type == type }?.data
        }.first
    }

    nonisolated private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }

    nonisolated private static func thumbnail(for image: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96
            ] as CFDictionary)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
