import AppKit
import ClipboardCore

/// Reports each new copy. macOS posts no notification for pasteboard changes, so this
/// polls `changeCount` the way every clipboard manager does.
@MainActor
final class PasteboardWatcher {
    static let interval: TimeInterval = 0.5

    /// The pasteboard's items, and the app that was frontmost when they were copied —
    /// `nil` when Perch itself put them there.
    var onCopy: (([ClipPasteboardItem], String?) -> Void)?

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int?
    private var ownChangeCount: Int?
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Starts watching, recording whatever is on the pasteboard right now first.
    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after Perch writes to the pasteboard, so that copy is not credited to
    /// whichever app happens to be frontmost.
    func noteOwnWrite() {
        ownChangeCount = pasteboard.changeCount
    }

    /// Checks now instead of waiting for the next tick.
    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let pasteboardItems = pasteboard.pasteboardItems ?? []
        let isConcealed = pasteboardItems.contains { item in
            item.types.contains { ClipCapturePolicy.ignoredTypes.contains($0.rawValue) }
        }
        guard !isConcealed else { return }

        let items = pasteboardItems.map { item in
            let types = item.types.map(\.rawValue)
            var data: [String: Data] = [:]
            for type in item.types where ClipCapturePolicy.isStoredType(type.rawValue) {
                data[type.rawValue] = item.data(forType: type)
            }
            return ClipPasteboardItem(types: types, data: data)
        }
        let source = changeCount == ownChangeCount
            ? nil
            : NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        onCopy?(items, source)
    }
}
