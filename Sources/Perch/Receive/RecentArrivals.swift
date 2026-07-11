import AppKit
import Darwin
import UniformTypeIdentifiers

/// A file that recently landed in a watched folder, offered on the shelf as a dimmed
/// "ghost" row the user can tap to bring aboard.
struct ArrivalOffer: Identifiable, Equatable {
    let url: URL
    let addedAt: Date

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// "Downloads" / "Desktop" — the folder the file arrived in, for the subtitle.
    var locationName: String {
        url.deletingLastPathComponent().lastPathComponent
    }
}

/// OFFER: surfaces files that just arrived in Downloads / Desktop as ghost rows.
///
/// Directory changes trigger a debounced `refresh`; the controller either updates a
/// visible shelf or briefly reveals a hidden one. Anti-annoyance rules:
///  - only files added within the last `window` (15 min), newest first, capped at 3;
///  - a file is offered in at most `maxReveals` reveals, then never again;
///  - dismissing a ghost from its context menu silences that file permanently;
///  - files Perch itself placed (vends, return-to-origin) are excluded by the caller;
///  - `suppressed` hides ghosts while a system drag is in flight so drop geometry
///    never shifts mid-drag.
@MainActor
final class RecentArrivals: ObservableObject {
    /// Master switch, user-toggled from Behavior settings. Default on (an unset value
    /// reads as true) — the worst case is a few dim rows on an already-summoned shelf.
    static let enabledKey = "Perch.OfferRecentArrivals"

    static let window: TimeInterval = 15 * 60
    static let maxOffers = 3
    static let maxReveals = 3

    private static let dismissedKey = "Perch.ArrivalDismissed"
    private static let revealCountsKey = "Perch.ArrivalRevealCounts"
    /// In-progress download artifacts that must never be offered.
    private static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp"
    ]

    @Published private(set) var offers: [ArrivalOffer] = []
    /// True while a system drag is in flight: ghosts hide so they never shift the
    /// drop target under the cursor.
    @Published var suppressed = false

    /// path → when its ghost was dismissed or excluded; never offered again.
    private var dismissedPaths: [String: Date]
    /// path → number of reveals its ghost has appeared in.
    private var revealCounts: [String: Int]
    /// Directory event sources stay alive for the lifetime of the app. Chrome writes a
    /// temporary `.crdownload` and then renames it, so directory-level events are the
    /// reliable signal; the controller debounces and rescans after either operation.
    private var directorySources: [DispatchSourceFileSystemObject] = []

    init() {
        dismissedPaths = UserDefaults.standard.dictionary(forKey: Self.dismissedKey)
            as? [String: Date] ?? [:]
        revealCounts = UserDefaults.standard.dictionary(forKey: Self.revealCountsKey)
            as? [String: Int] ?? [:]
    }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Watch Downloads and Desktop for additions, writes, and Chrome's final rename.
    /// The callback is intentionally only a change signal: eligibility is decided by
    /// `refresh`, after the controller's debounce lets the final file settle.
    func startWatching(onChange: @escaping @MainActor () -> Void) {
        stopWatching()
        for directory in Self.watchedDirectories() {
            let descriptor = open(directory.path, O_EVTONLY)
            guard descriptor >= 0 else {
                NSLog("Perch could not watch arrival folder \(directory.path)")
                continue
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler {
                Task { @MainActor in onChange() }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            directorySources.append(source)
        }
    }

    func stopWatching() {
        directorySources.forEach { $0.cancel() }
        directorySources.removeAll()
    }

    /// Re-scan the watched folders. `markRevealed` should be true when this refresh
    /// accompanies an actual shelf reveal — it spends one of each shown file's offer
    /// chances (skipped while suppressed: an invisible ghost consumes nothing).
    func refresh(excluding excludedPaths: Set<String>, markRevealed: Bool = false) {
        guard enabled else {
            if !offers.isEmpty { offers = [] }
            return
        }
        prune()

        let now = Date()
        var candidates: [ArrivalOffer] = []
        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey, .fileSizeKey
        ]
        for directory in Self.watchedDirectories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            ) else { continue }

            for url in entries {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isDirectory != true,
                      (values.fileSize ?? 0) > 0,
                      !Self.partialExtensions.contains(url.pathExtension.lowercased()),
                      let added = values.addedToDirectoryDate ?? values.creationDate,
                      now.timeIntervalSince(added) < Self.window
                else { continue }

                let path = url.path
                guard dismissedPaths[path] == nil,
                      revealCounts[path, default: 0] < Self.maxReveals,
                      !excludedPaths.contains(path)
                else { continue }

                candidates.append(ArrivalOffer(url: url, addedAt: added))
            }
        }

        let fresh = Array(candidates.sorted { $0.addedAt > $1.addedAt }.prefix(Self.maxOffers))
        if markRevealed, !suppressed {
            for offer in fresh {
                revealCounts[offer.id, default: 0] += 1
            }
            persist()
        }
        if fresh != offers {
            offers = fresh
        }
    }

    /// The user dismissed a ghost from its context menu: never offer it again.
    func dismiss(_ offer: ArrivalOffer) {
        dismissedPaths[offer.id] = Date()
        persist()
        offers.removeAll { $0.id == offer.id }
    }

    /// Silence paths Perch itself just placed (vended files, returns-to-origin) so the
    /// shelf never offers back what it just put down.
    func excludePermanently(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        let now = Date()
        for path in paths {
            dismissedPaths[path] = now
        }
        persist()
        offers.removeAll { paths.contains($0.id) }
    }

    private static func watchedDirectories() -> [URL] {
        let fileManager = FileManager.default
        let kinds: [FileManager.SearchPathDirectory] = [.downloadsDirectory, .desktopDirectory]
        return kinds.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
    }

    /// Drop bookkeeping for files that can no longer qualify anyway (dismissed longer
    /// ago than the window, or counted files that left the window), so the persisted
    /// dictionaries stay a handful of entries.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.window)
        dismissedPaths = dismissedPaths.filter { $0.value > cutoff }
        revealCounts = revealCounts.filter { path, _ in
            guard let values = try? URL(fileURLWithPath: path).resourceValues(
                forKeys: [.addedToDirectoryDateKey, .creationDateKey]
            ) else { return false }
            guard let added = values.addedToDirectoryDate ?? values.creationDate else { return false }
            return added > cutoff
        }
    }

    private func persist() {
        UserDefaults.standard.set(dismissedPaths, forKey: Self.dismissedKey)
        UserDefaults.standard.set(revealCounts, forKey: Self.revealCountsKey)
    }
}
