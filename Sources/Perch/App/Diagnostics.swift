import AppKit
import ApplicationServices
import ServiceManagement

/// One line of the troubleshooting checklist.
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
            checks.append(folderAccessCheck(name: location.displayName, url: url))
        }
        checks.append(screenshotCheck())
        checks.append(loginItemCheck())
        if PerchSettings.labsFlag(PerchSettings.snapBesideDock) {
            checks.append(accessibilityCheck())
        }
        checks.append(clipboardCheck(clipboard))
        return checks
    }

    // MARK: Checks

    private static func recentArrivalsCheck() -> DiagnosticCheck {
        if PerchSettings.flag(PerchSettings.offerRecentArrivals, default: true) {
            return DiagnosticCheck(
                title: "Recent arrivals",
                status: .ok,
                detail: "On. New downloads and screenshots are offered on the shelf."
            )
        }
        return DiagnosticCheck(
            title: "Recent arrivals",
            status: .problem,
            detail: "Off, so new downloads and screenshots are never offered.",
            fix: .init(title: "Turn On") {
                UserDefaults.standard.set(true, forKey: PerchSettings.offerRecentArrivals)
            }
        )
    }

    private static func folderAccessCheck(name: String, url: URL) -> DiagnosticCheck {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return DiagnosticCheck(
                title: "\(name) folder",
                status: .ok,
                detail: "Perch can read \(abbreviated(url))."
            )
        } catch {
            return DiagnosticCheck(
                title: "\(name) folder",
                status: .problem,
                detail: "macOS is blocking Perch from reading \(abbreviated(url)), so new "
                    + "files there never show up. Allow Perch under Files and Folders.",
                fix: .init(title: "Open Privacy Settings") {
                    openSettings("Privacy_FilesAndFolders")
                }
            )
        }
    }

    private static func screenshotCheck() -> DiagnosticCheck {
        if ScreenshotLocation.savesToClipboard {
            return DiagnosticCheck(
                title: "Screenshots",
                status: .note,
                detail: "Screenshots are copied to the clipboard instead of saved, so they "
                    + "never appear on the shelf. Change this in the Screenshot app’s Options."
            )
        }
        let folder = ScreenshotLocation.folder
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return DiagnosticCheck(
                title: "Screenshots",
                status: .problem,
                detail: "Screenshots are set to save to \(abbreviated(folder)), which doesn’t exist."
            )
        }
        let watched = RecentArrivals.watchingPaths.contains(folder.resolvingSymlinksInPath().path)
        guard watched || !PerchSettings.flag(PerchSettings.offerRecentArrivals, default: true) else {
            return DiagnosticCheck(
                title: "Screenshots",
                status: .problem,
                detail: "Screenshots now save to \(abbreviated(folder)). Restart Perch to start watching it.",
                fix: .init(title: "Restart Perch") { Relauncher.restart() }
            )
        }
        return DiagnosticCheck(
            title: "Screenshots",
            status: .ok,
            detail: "Saved to \(abbreviated(folder)), which Perch watches."
        )
    }

    private static func loginItemCheck() -> DiagnosticCheck {
        let title = "Launch at login"
        guard Bundle.main.bundleIdentifier != nil else {
            return DiagnosticCheck(title: title, status: .note, detail: "Not available in this build.")
        }
        let bundlePath = Bundle.main.bundlePath
        let inApplications = bundlePath.hasPrefix("/Applications/")
            || bundlePath.hasPrefix(NSHomeDirectory() + "/Applications/")
        switch SMAppService.mainApp.status {
        case .enabled where !inApplications:
            return DiagnosticCheck(
                title: title,
                status: .problem,
                detail: "On, but Perch is running from \(abbreviated(URL(fileURLWithPath: bundlePath))). "
                    + "Move it to Applications so it keeps launching."
            )
        case .enabled:
            return DiagnosticCheck(title: title, status: .ok, detail: "On.")
        case .requiresApproval:
            return DiagnosticCheck(
                title: title,
                status: .problem,
                detail: "Waiting for approval in System Settings › Login Items.",
                fix: .init(title: "Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
            )
        case .notRegistered:
            return DiagnosticCheck(title: title, status: .note, detail: "Off.")
        case .notFound:
            return DiagnosticCheck(
                title: title,
                status: .problem,
                detail: "macOS can’t find Perch’s login item. Turn Launch at login off and on again."
            )
        @unknown default:
            return DiagnosticCheck(title: title, status: .note, detail: "Unknown status.")
        }
    }

    private static func accessibilityCheck() -> DiagnosticCheck {
        if DockGeometryReader.isTrusted {
            return DiagnosticCheck(
                title: "Accessibility",
                status: .ok,
                detail: "Allowed, so Snap beside the Dock can read the Dock’s size."
            )
        }
        return DiagnosticCheck(
            title: "Accessibility",
            status: .problem,
            detail: "Snap beside the Dock is on but Perch isn’t allowed under Accessibility.",
            fix: .init(title: "Open Privacy Settings") { openSettings("Privacy_Accessibility") }
        )
    }

    private static func clipboardCheck(_ clipboard: ClipboardCoordinator) -> DiagnosticCheck {
        let title = "Perch Clipboard"
        guard clipboard.isEnabled else {
            return DiagnosticCheck(title: title, status: .note, detail: "Off.")
        }
        if let error = clipboard.errorMessage {
            return DiagnosticCheck(title: title, status: .problem, detail: error)
        }
        return DiagnosticCheck(
            title: title,
            status: .ok,
            detail: "\(clipboard.hotKey.displayString) opens it. If that does nothing, another "
                + "app may use the same shortcut; pick a new one in Settings › Clipboard."
        )
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
        var lines = [
            "Perch \(version) (\(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            ""
        ]
        for check in checks {
            let mark: String
            switch check.status {
            case .ok: mark = "OK  "
            case .problem: mark = "FAIL"
            case .note: mark = "NOTE"
            }
            lines.append("[\(mark)] \(check.title): \(check.detail)")
        }
        lines.append("")
        lines.append(errors.isEmpty ? "No recent errors." : "Recent errors:")
        lines += errors
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
