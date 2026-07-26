import AppKit
import QuickLookThumbnailing

/// Generates and caches real Quick Look content thumbnails (image/PDF/document previews)
/// for stored items, off the main thread. `thumbnail(for:)` returns a cached preview if
/// one exists, otherwise kicks off generation and returns nil (the row shows the
/// file-type icon until the preview arrives). Only genuine *content* thumbnails are
/// cached — files Quick Look can't preview fall back to the icon permanently.
@MainActor
final class ThumbnailStore: ObservableObject {
    /// Republished whenever a new thumbnail lands, so observing rows refresh.
    @Published private var cache: [UUID: CachedThumbnail] = [:]
    private var inFlight: [UUID: CGFloat] = [:]

    private struct CachedThumbnail {
        let image: NSImage
        let pointSize: CGFloat
    }

    /// Requests enough resolution for the surface using the preview. Ordinary rows ask
    /// for 40 points; the square deck can ask for a much larger sample without making
    /// every cached list thumbnail pay that memory cost.
    func thumbnail(for item: StoredItem, pointSize: CGFloat = 40) -> NSImage? {
        let requestedSize = max(40, pointSize.rounded(.up))
        let cached = cache[item.id]
        if (cached?.pointSize ?? 0) < requestedSize {
            requestIfNeeded(for: item, pointSize: requestedSize)
        }
        return cached?.image
    }

    private func requestIfNeeded(for item: StoredItem, pointSize: CGFloat) {
        guard (cache[item.id]?.pointSize ?? 0) < pointSize,
              (inFlight[item.id] ?? 0) < pointSize else { return }
        guard let url = item.backingFileURLs().first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else { return }

        inFlight[item.id] = pointSize
        let id = item.id
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pointSize, height: pointSize),
            scale: scale,
            representationTypes: .thumbnail
        )

        Task { [weak self] in
            let representation = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request)
            guard let self else { return }
            if self.inFlight[id] == pointSize {
                self.inFlight[id] = nil
            }
            if let representation {
                if (self.cache[id]?.pointSize ?? 0) < pointSize {
                    self.cache[id] = CachedThumbnail(
                        image: representation.nsImage,
                        pointSize: pointSize
                    )
                }
            }
        }
    }
}
