import AppKit
import Darwin
import SmartPerchCore
import UniformTypeIdentifiers

/// OFFER: surfaces files that just arrived in Downloads / Desktop as ghost rows.
///
/// Directory changes trigger a debounced `refresh`; the controller either updates a
/// visible shelf or briefly reveals a hidden one. Anti-annoyance rules:
///  - only files added within the last `window` (15 min), newest first;
///  - Downloads files completed within five seconds collapse into one session;
///  - at most three sessions/individual Desktop files are presented;
///  - a file is offered in at most `maxReveals` reveals, then never again;
///  - dismissing a ghost from its context menu silences that file permanently;
///  - files Perch itself placed (vends, return-to-origin) are excluded by the caller;
///  - `suppressed` hides ghosts while a system drag is in flight so drop geometry
///    never shifts mid-drag.
@MainActor
final class RecentArrivals: ObservableObject {
    /// Master switch, user-toggled from Behavior settings. Default on (an unset value
    /// reads as true) — the worst case is a few dim rows on an already-summoned shelf.
    static let enabledKey = PerchSettings.offerRecentArrivals

    static let window: TimeInterval = 15 * 60
    static let maxSessions = 3
    static let maxReveals = 3

    private static let dismissedKey = PerchSettings.arrivalDismissed
    private static let revealCountsKey = PerchSettings.arrivalRevealCounts
    /// In-progress download artifacts that must never be offered.
    private static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp"
    ]

    private(set) var sessions: [ArrivalSession] = []
    @Published private(set) var visibleGhosts: [ArrivalGhost] = []
    /// Temporary presentation names for files that have not been adopted. The SQLite
    /// event log remains untouched until an actual drop/adoption occurs.
    @Published private(set) var smartNamesByPath: [String: String] = [:]
    /// True while a system drag is in flight: ghosts hide so they never shift the
    /// drop target under the cursor.
    @Published var suppressed = false

    /// path → when its ghost was dismissed or excluded; never offered again.
    private var dismissedPaths: [String: Date]
    /// path → number of reveals its ghost has appeared in.
    private var revealCounts: [String: Int]
    /// Stable while any member remains visible, so adopting one file does not turn the
    /// rest of its session into a new behavioral batch.
    private var sessionIDByPath: [String: UUID] = [:]
    private var sessionTotalCountByID: [UUID: Int] = [:]
    /// A screenshot's desktop context is meaningful only at arrival time. Cache it by
    /// path so later refreshes and a delayed ghost click reuse that original snapshot.
    private var screenshotContextByPath: [String: ScreenshotCaptureContext] = [:]
    private var expandedSessionIDs: Set<UUID> = []
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
        for (_, directory) in Self.watchedDirectories() {
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
            sessions = []
            expandedSessionIDs = []
            smartNamesByPath = [:]
            publishVisibleGhosts()
            return
        }
        prune()

        let now = Date()
        var candidates: [ArrivalOffer] = []
        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey, .fileSizeKey
        ]
        for (location, directory) in Self.watchedDirectories() {
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

                candidates.append(ArrivalOffer(
                    url: url,
                    addedAt: added,
                    location: location,
                    screenshotCaptureContext: screenshotContext(
                        for: url,
                        addedAt: added,
                        now: now
                    )
                ))
            }
        }

        let groups = Array(
            DownloadSessionGrouper.group(candidates).prefix(Self.maxSessions)
        )
        var usedSessionIDs: Set<UUID> = []
        let fresh = groups.map { offers -> ArrivalSession in
            let existingID = offers
                .compactMap { sessionIDByPath[$0.id] }
                .first { !usedSessionIDs.contains($0) }
            let sessionID = existingID ?? UUID()
            usedSessionIDs.insert(sessionID)
            let totalFileCount = max(
                sessionTotalCountByID[sessionID, default: 0],
                offers.count
            )
            sessionTotalCountByID[sessionID] = totalFileCount
            for offer in offers {
                sessionIDByPath[offer.id] = sessionID
            }
            return ArrivalSession(
                id: sessionID,
                offers: offers,
                totalFileCount: totalFileCount
            )
        }

        if markRevealed, !suppressed {
            for offer in fresh.flatMap(\.offers) {
                revealCounts[offer.id, default: 0] += 1
            }
            persist()
        }

        sessions = fresh
        let freshPaths = Set(fresh.flatMap(\.offers).map(\.id))
        smartNamesByPath = smartNamesByPath.filter {
            freshPaths.contains($0.key)
        }
        expandedSessionIDs.formIntersection(
            Set(fresh.filter(\.isBatch).map(\.id))
        )
        publishVisibleGhosts()
    }

    /// The user dismissed a ghost from its context menu: never offer it again.
    func dismiss(_ offer: ArrivalOffer) {
        dismissedPaths[offer.id] = Date()
        persist()
        removeVisibleOffers(withIDs: [offer.id])
    }

    /// Dismiss every remaining member of a download session without touching the files.
    func dismiss(_ session: ArrivalSession) {
        let now = Date()
        for offer in session.offers {
            dismissedPaths[offer.id] = now
        }
        persist()
        removeVisibleOffers(withIDs: Set(session.offers.map(\.id)))
    }

    func expand(_ session: ArrivalSession) {
        guard session.isBatch else { return }
        expandedSessionIDs.insert(session.id)
        publishVisibleGhosts()
    }

    func smartName(for offer: ArrivalOffer) -> String? {
        smartNamesByPath[offer.id]
    }

    func setSmartName(_ name: String, forPath path: String) {
        guard sessions.contains(where: { session in
            session.offers.contains(where: { $0.id == path })
        }) else {
            return
        }
        smartNamesByPath[path] = name
    }

    /// Drop the generated names when Smart Perch is switched off, so ghosts fall back to
    /// their real filenames instead of keeping labels nothing is maintaining any more.
    func clearSmartNames() {
        guard !smartNamesByPath.isEmpty else { return }
        smartNamesByPath = [:]
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
        removeVisibleOffers(withIDs: Set(paths))
    }

    /// A promise-backed drag (notably the floating screenshot thumbnail) gives Perch
    /// only the file it wrote into the holding directory, not the original Desktop
    /// path. Silence a unique, very recent filename + size match so the same screenshot
    /// cannot reappear as a ghost row immediately after it lands as a stored item.
    func excludeRecentlyMatchingCopies(
        of materializedURLs: [URL],
        droppedAt: Date
    ) {
        let fingerprints = Set(
            materializedURLs.compactMap(Self.fileFingerprint)
        )
        guard !fingerprints.isEmpty else { return }

        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey, .fileSizeKey
        ]
        var candidates: [ArrivalCopyCandidate] = []
        for (_, directory) in Self.watchedDirectories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            ) else {
                continue
            }

            for url in entries {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isDirectory != true,
                      let byteCount = values.fileSize,
                      byteCount > 0,
                      let addedAt = values.addedToDirectoryDate ?? values.creationDate
                else {
                    continue
                }
                candidates.append(
                    ArrivalCopyCandidate(
                        path: url.path,
                        fingerprint: ArrivalFileFingerprint(
                            name: url.lastPathComponent,
                            byteCount: byteCount
                        ),
                        addedAt: addedAt
                    )
                )
            }
        }

        excludePermanently(
            ArrivalCopyMatcher.matchingPaths(
                materializedFingerprints: fingerprints,
                candidates: candidates,
                droppedAt: droppedAt
            )
        )
    }

    private static func fileFingerprint(for url: URL) -> ArrivalFileFingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let byteCount = values.fileSize,
              byteCount > 0,
              !url.lastPathComponent.isEmpty else {
            return nil
        }
        return ArrivalFileFingerprint(
            name: url.lastPathComponent,
            byteCount: byteCount
        )
    }

    private static func watchedDirectories() -> [(ArrivalLocation, URL)] {
        let fileManager = FileManager.default
        let kinds: [(ArrivalLocation, FileManager.SearchPathDirectory)] = [
            (.downloads, .downloadsDirectory),
            (.desktop, .desktopDirectory)
        ]
        return kinds.compactMap { location, kind in
            fileManager.urls(for: kind, in: .userDomainMask).first.map { (location, $0) }
        }
    }

    private func screenshotContext(
        for url: URL,
        addedAt: Date,
        now: Date
    ) -> ScreenshotCaptureContext? {
        if let cached = screenshotContextByPath[url.path] {
            return cached
        }

        // Never match an older screenshot against whatever windows happen to be open
        // now. Directory notifications reach this scan after a 700 ms settle delay.
        guard now.timeIntervalSince(addedAt) >= -2,
              now.timeIntervalSince(addedAt) <= 8,
              let context = ScreenshotWindowContextCapture.captureContext(
                for: url,
                capturedAt: now
              )
        else {
            return nil
        }
        screenshotContextByPath[url.path] = context
        NSLog(
            "Perch matched fresh screenshot \(url.lastPathComponent) to "
                + "\(context.ownerName) at "
                + "\(Int((context.visibleCoverage * 100).rounded()))% visible coverage"
        )
        return context
    }

    private func removeVisibleOffers(withIDs removedIDs: Set<String>) {
        smartNamesByPath = smartNamesByPath.filter {
            !removedIDs.contains($0.key)
        }
        sessions = sessions.compactMap { session in
            let remaining = session.offers.filter { !removedIDs.contains($0.id) }
            guard !remaining.isEmpty else {
                expandedSessionIDs.remove(session.id)
                return nil
            }
            return ArrivalSession(
                id: session.id,
                offers: remaining,
                totalFileCount: session.totalFileCount
            )
        }
        publishVisibleGhosts()
    }

    private func publishVisibleGhosts() {
        visibleGhosts = sessions.flatMap { session -> [ArrivalGhost] in
            guard session.isBatch else {
                return session.offers.map {
                    ArrivalGhost.offer($0, session: session)
                }
            }
            guard expandedSessionIDs.contains(session.id) else {
                return [ArrivalGhost.summary(session, action: .expand)]
            }
            return [ArrivalGhost.summary(session, action: .addAll)]
                + session.offers.map {
                    ArrivalGhost.offer($0, session: session)
                }
        }
    }

    /// Drop bookkeeping for files that can no longer qualify anyway (dismissed longer
    /// ago than the window, or counted files that left the window), so the persisted
    /// dictionaries stay a handful of entries.
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.window)
        let activePaths = Set(sessions.flatMap(\.offers).map(\.id))
        dismissedPaths = dismissedPaths.filter { $0.value > cutoff }
        revealCounts = revealCounts.filter { path, _ in
            guard let values = try? URL(fileURLWithPath: path).resourceValues(
                forKeys: [.addedToDirectoryDateKey, .creationDateKey]
            ) else { return false }
            guard let added = values.addedToDirectoryDate ?? values.creationDate else { return false }
            return added > cutoff
        }
        sessionIDByPath = sessionIDByPath.filter { path, _ in
            activePaths.contains(path)
                || revealCounts[path] != nil
                || dismissedPaths[path] != nil
        }
        screenshotContextByPath = screenshotContextByPath.filter { path, _ in
            activePaths.contains(path)
                || revealCounts[path] != nil
                || dismissedPaths[path] != nil
        }
        smartNamesByPath = smartNamesByPath.filter {
            activePaths.contains($0.key)
        }
        let retainedSessionIDs = Set(sessionIDByPath.values)
        sessionTotalCountByID = sessionTotalCountByID.filter {
            retainedSessionIDs.contains($0.key)
        }
    }

    private func persist() {
        UserDefaults.standard.set(dismissedPaths, forKey: Self.dismissedKey)
        UserDefaults.standard.set(revealCounts, forKey: Self.revealCountsKey)
    }
}
