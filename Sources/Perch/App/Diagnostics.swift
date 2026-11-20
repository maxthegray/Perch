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
        let watching = RecentArrivals.watchingPaths.contains(url.resolvingSymlinksInPath().path)
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return DiagnosticCheck(
                title: key,
                status: watching ? .ok : .problem,
                detail: "\(path)  read=ok  watch=\(watching ? "ok" : "none")",
                fix: watching ? nil : .init(title: "Restart") { Relauncher.restart() }
            )
        } catch {
            return DiagnosticCheck(
                title: key,
                status: .problem,
                detail: "\(path)  read=\(errorCode(error))  watch=\(watching ? "ok" : "none")",
                fix: .init(title: "Files & Folders…") { openSettings("Privacy_FilesAndFolders") }
            )
        }
    }

    private static func screenshotCheck() -> DiagnosticCheck {
        let folder = ScreenshotLocation.folder
        let target = ScreenshotLocation.savesToClipboard ? "clipboard" : "file"
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let watched = RecentArrivals.watchingPaths.contains(folder.resolvingSymlinksInPath().path)
        let detail = "location=\(abbreviated(folder))  target=\(target)  exists=\(exists)  watched=\(watched)"

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
                fix: .init(title: "Login Items…") { SMAppService.openSystemSettingsLoginItems() }
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
            fix: trusted ? nil : .init(title: "Accessibility…") { openSettings("Privacy_Accessibility") }
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

    // MARK: Report

    static func report(checks: [DiagnosticCheck], errors: [String]) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var lines = [
            "perch     \(version) (\(build))",
            "macos     \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "arch      \(architecture)",
            "bundle    \(abbreviated(Bundle.main.bundleURL))",
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
