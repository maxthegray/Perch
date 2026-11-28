import AppKit
import ApplicationServices
import ServiceManagement

/// One line of the troubleshooting checklist: a short key and its raw value.
struct DiagnosticCheck: Identifiable {
    enum Status { case ok, problem, note }

    struct Fix {
        let title: String
        let perform: @MainActor () -> Void
    }

    let id = UUID()
    let title: String
    let status: Status
    let detail: String
    var fix: Fix?
}

/// Read-only checks of the things that most often stop Perch from working, each with
/// the one-step fix when there is one. Running them changes nothing.
@MainActor
enum Diagnostics {
    static func run(clipboard: ClipboardCoordinator) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []
        checks.append(recentArrivalsCheck())
        for (location, url) in RecentArrivals.watchedDirectories() {
            checks.append(folderAccessCheck(key: "watch.\(location.rawValue)", url: url))
        }
        for (location, url) in RecentArrivals.watchedDirectories() {
            checks.append(newestFilesCheck(key: "newest.\(location.rawValue)", url: url))
        }
        checks.append(screenshotCheck())
        checks.append(loginItemCheck())
        if PerchSettings.labsFlag(PerchSettings.snapBesideDock) {
            checks.append(accessibilityCheck())
        }
        checks.append(clipboardCheck(clipboard))
        checks.append(DiagnosticCheck(
            title: "labs",
            status: .note,
            detail: LabsAccess.isUnlocked ? "unlocked" : "locked"
        ))
        return checks
    }

    // MARK: Checks

    private static func recentArrivalsCheck() -> DiagnosticCheck {
        let enabled = PerchSettings.flag(PerchSettings.offerRecentArrivals, default: true)
        return DiagnosticCheck(
            title: "arrivals.enabled",
            status: enabled ? .ok : .problem,
            detail: String(enabled),
            fix: enabled ? nil : .init(title: "Enable") {
                UserDefaults.standard.set(true, forKey: PerchSettings.offerRecentArrivals)
            }
        )
    }

    private static func folderAccessCheck(key: String, url: URL) -> DiagnosticCheck {
        let path = abbreviated(url)
        let watch = RecentArrivals.watchState(for: url)
        let watching = watch == .ok
        var suffix = ""
        if key == "watch.desktop" {
            let synced = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?
                .isUbiquitousItem == true
            suffix = "  icloud=\(synced ? "on" : "off")"
        }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return DiagnosticCheck(
                title: key,
                status: watching ? .ok : .problem,
                detail: "\(path)  read=ok  watch=\(watch.rawValue)\(suffix)",
                fix: watching ? nil : .init(title: "Restart") { Relauncher.restart() }
            )
        } catch {
            return DiagnosticCheck(
                title: key,
                status: .problem,
                detail: "\(path)  read=\(errorCode(error))  watch=\(watch.rawValue)\(suffix)",
                fix: .init(title: "Files & Folders") { openSettings("Privacy_FilesAndFolders") }
            )
        }
    }

    private static func screenshotCheck() -> DiagnosticCheck {
        let folder = ScreenshotLocation.folder
        let target = ScreenshotLocation.savesToClipboard ? "clipboard" : "file"
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let watched = RecentArrivals.watchState(for: folder) == .ok
        let thumbnail = ScreenshotLocation.showsThumbnail ? "on" : "off"
        let detail = "location=\(abbreviated(folder))  target=\(target)  exists=\(exists)  "
            + "watched=\(watched)  thumbnail=\(thumbnail)"

        if target == "clipboard" {
            return DiagnosticCheck(title: "screencapture", status: .note, detail: detail)
        }
        if !exists {
            return DiagnosticCheck(title: "screencapture", status: .problem, detail: detail)
        }
        if !watched {
            return DiagnosticCheck(
                title: "screencapture",
                status: .problem,
                detail: detail,
                fix: .init(title: "Restart") { Relauncher.restart() }
            )
        }
        return DiagnosticCheck(title: "screencapture", status: .ok, detail: detail)
    }

    /// The newest files in a watched folder with both of their dates. Perch judges
    /// freshness by date added, so a just-arrived file showing an old one is skipped.
    private static func newestFilesCheck(key: String, url: URL, now: Date = Date()) -> DiagnosticCheck {
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        )) ?? []
        let dated = entries.compactMap { file -> (String, Date?, Date?)? in
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isDirectory != true else { return nil }
            return (file.lastPathComponent, values.addedToDirectoryDate, values.creationDate)
        }
        let newest = dated
            .sorted { max($0.1 ?? .distantPast, $0.2 ?? .distantPast) > max($1.1 ?? .distantPast, $1.2 ?? .distantPast) }
            .prefix(2)
            .map { name, added, created in
                "\(name) added=\(age(of: added, now: now)) created=\(age(of: created, now: now))"
            }
        return DiagnosticCheck(
            title: key,
            status: .note,
            detail: newest.isEmpty ? "empty" : newest.joined(separator: "  |  ")
        )
    }

    static func age(of date: Date?, now: Date) -> String {
        guard let date else { return "none" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 { return "in \(-seconds)s" }
        if seconds < 120 { return "\(seconds)s" }
        if seconds < 7200 { return "\(seconds / 60)m" }
        if seconds < 172_800 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    private static func loginItemCheck() -> DiagnosticCheck {
        let title = "login.item"
        guard Bundle.main.bundleIdentifier != nil else {
            return DiagnosticCheck(title: title, status: .note, detail: "unavailable (unbundled)")
        }
        let bundlePath = Bundle.main.bundlePath
        let inApplications = bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
        let path = "path=\(abbreviated(URL(fileURLWithPath: bundlePath)))"
        switch SMAppService.mainApp.status {
        case .enabled:
            return DiagnosticCheck(
                title: title,
                status: inApplications ? .ok : .problem,
                detail: "status=enabled  \(path)"
            )
        case .requiresApproval:
            return DiagnosticCheck(
                title: title,
                status: .problem,
                detail: "status=requiresApproval  \(path)",
                fix: .init(title: "Login Items") { SMAppService.openSystemSettingsLoginItems() }
            )
        case .notRegistered:
            return DiagnosticCheck(title: title, status: .note, detail: "status=notRegistered  \(path)")
        case .notFound:
            return DiagnosticCheck(title: title, status: .problem, detail: "status=notFound  \(path)")
        @unknown default:
            return DiagnosticCheck(title: title, status: .note, detail: "status=unknown  \(path)")
        }
    }

    private static func accessibilityCheck() -> DiagnosticCheck {
        let trusted = DockGeometryReader.isTrusted
        return DiagnosticCheck(
            title: "ax.trusted",
            status: trusted ? .ok : .problem,
            detail: String(trusted),
            fix: trusted ? nil : .init(title: "Accessibility") { openSettings("Privacy_Accessibility") }
        )
    }

    private static func clipboardCheck(_ clipboard: ClipboardCoordinator) -> DiagnosticCheck {
        guard clipboard.isEnabled else {
            return DiagnosticCheck(title: "clipboard", status: .note, detail: "enabled=false")
        }
        let base = "enabled=true  hotkey=\(clipboard.hotKey.displayString)"
        if let error = clipboard.errorMessage {
            return DiagnosticCheck(title: "clipboard", status: .problem, detail: "\(base)  error=\(error)")
        }
        return DiagnosticCheck(title: "clipboard", status: .ok, detail: base)
    }

    // MARK: Recent errors

    /// The last few failures this run of Perch logged.
    static func recentErrors(limit: Int = 15) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let failureWords = ["fail", "could not", "couldn’t", "can't", "cannot", "error", "denied"]
        let lines = PerchLog.recent
            .filter { entry in
                let lowered = entry.message.lowercased()
                return failureWords.contains(where: lowered.contains)
            }
            .map { "\(formatter.string(from: $0.date))  \($0.message)" }
        return Array(lines.suffix(limit))
    }

    /// What the recent-arrivals watcher saw and decided this run, oldest first.
    static func recentArrivals() -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return PerchLog.arrivals.recent.map {
            "\(formatter.string(from: $0.date))  \($0.message)"
        }
    }

    /// Every Perch setting this install has written, scalar values only. Dictionaries are
    /// left out: they hold file paths (dismissed arrivals, reveal counts).
    static func settingsSnapshot(defaults: UserDefaults = .standard) -> [String] {
        defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("Perch.") }
            .compactMap { key, value -> String? in
                let name = String(key.dropFirst("Perch.".count))
                switch value {
                case let number as NSNumber:
                    return "\(name)=\(CFGetTypeID(number) == CFBooleanGetTypeID() ? String(number.boolValue) : number.stringValue)"
                case let string as String:
                    return "\(name)=\(string)"
                case let strings as [String]:
                    return "\(name)=\(strings.joined(separator: ","))"
                default:
                    return nil
                }
            }
            .sorted()
    }

    /// The last lines Perch logged this run, failures or not.
    static func recentLog(limit: Int = 50) -> [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return PerchLog.recent.suffix(limit).map {
            "\(formatter.string(from: $0.date))  \($0.message)"
        }
    }

    /// The whole report as Troubleshoot copies it, for Report a Problem.
    static func fullReport(clipboard: ClipboardCoordinator) -> String {
        report(
            checks: run(clipboard: clipboard),
            errors: recentErrors(),
            arrivals: recentArrivals(),
            settings: settingsSnapshot(),
            log: recentLog()
        )
    }

    // MARK: Report

    static func report(
        checks: [DiagnosticCheck],
        errors: [String],
        arrivals: [String] = [],
        settings: [String] = [],
        log: [String] = []
    ) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        var lines = [
            "perch     \(version) (\(build))",
            "macos     \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "arch      \(architecture)",
            "bundle    \(abbreviated(Bundle.main.bundleURL))",
            "clock     \(clock.string(from: Date()))  tz=\(TimeZone.current.identifier)",
            ""
        ]
        let width = (checks.map(\.title.count).max() ?? 0) + 2
        for check in checks {
            lines.append(
                "\(mark(for: check.status))  "
                    + check.title.padding(toLength: width, withPad: " ", startingAt: 0)
                    + check.detail
            )
        }
        lines.append("")
        lines.append("log (\(errors.count))")
        lines += errors
        lines.append("")
        lines.append("arrivals (\(arrivals.count))")
        lines += arrivals
        lines.append("")
        lines.append("settings (\(settings.count))")
        lines += settings
        lines.append("")
        lines.append("recent log (\(log.count))")
        lines += log
        return lines.joined(separator: "\n")
    }

    static func mark(for status: DiagnosticCheck.Status) -> String {
        switch status {
        case .ok: return "ok  "
        case .problem: return "FAIL"
        case .note: return "--  "
        }
    }

    // MARK: Helpers

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// `NSCocoaErrorDomain 257 / NSPOSIXErrorDomain 1` — the codes, not the sentence.
    private static func errorCode(_ error: Error) -> String {
        let nsError = error as NSError
        var code = "\(nsError.domain) \(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            code += " / \(underlying.domain) \(underlying.code)"
        }
        return code
    }

    private static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
