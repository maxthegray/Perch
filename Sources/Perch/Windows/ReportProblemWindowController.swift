import AppKit
import SwiftUI

/// Owns the Report a Problem window. Perch is an accessory app, so showing it also
/// activates the app.
@MainActor
final class ReportProblemWindowController {
    private let clipboard: ClipboardCoordinator
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    init(clipboard: ClipboardCoordinator) {
        self.clipboard = clipboard
    }

    static var isAvailable: Bool { ProblemReportForm.perch != nil }

    func show() {
        guard let form = ProblemReportForm.perch else { return }
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let clipboard = clipboard
        let view = ReportProblemView(
            form: form,
            makeReport: { Diagnostics.fullReport(clipboard: clipboard) },
            close: { [weak self] in self?.window?.close() }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = "Report a Problem"
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        closeObserver.map(NotificationCenter.default.removeObserver)
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.window = nil }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
