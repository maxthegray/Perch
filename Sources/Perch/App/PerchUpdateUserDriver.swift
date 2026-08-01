import AppKit
import Sparkle

/// Sparkle's update flow with one screen replaced: the "an update is available" offer.
///
/// Sparkle's own alert reserves a large release-notes pane whether the release is a
/// rewrite or a one-line fix, which turned every update into a wall of text to dismiss.
/// This shows a plain alert instead — what, from what, and a link for anyone who does
/// want the changelog — and hands the answer straight back to Sparkle.
///
/// Everything else (permission, download and extraction progress, installation, errors)
/// is forwarded untouched to `SPUStandardUserDriver`. Only the offer is ours, and only
/// when the update has not been downloaded yet: an already-downloaded or installing
/// update goes through Sparkle's own screens, which know how to describe those states.
@MainActor
final class PerchUpdateUserDriver: NSObject, SPUUserDriver {
    /// Where "what changed" goes when the appcast names no notes of its own.
    private static let releasesPage = URL(string: "https://github.com/maxthegray/Perch/releases")!

    private let standard: SPUStandardUserDriver

    init(hostBundle: Bundle) {
        standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
    }

    // MARK: - The one screen this driver owns

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard state.stage == .notDownloaded else {
            standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(PerchProductIdentity.displayName) \(appcastItem.displayVersionString) is available"
        alert.informativeText = "You have \(Self.installedVersion)."
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        alert.accessoryView = changelogLink(for: appcastItem)

        // The alert has to come forward on its own: Perch is an accessory app with no
        // Dock tile, so nothing else would bring it to the front.
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: reply(.install)
        case .alertThirdButtonReturn: reply(.skip)
        default: reply(.dismiss)
        }
    }

    /// A quiet link rather than a button: reading the changelog is optional, and it opens
    /// in a browser so the alert itself never has to grow to hold it.
    private func changelogLink(for appcastItem: SUAppcastItem) -> NSView {
        let destination = appcastItem.fullReleaseNotesURL
            ?? appcastItem.releaseNotesURL
            ?? Self.releasesPage
        let button = NSButton()
        button.title = "See what changed"
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
        )
        button.target = self
        button.action = #selector(openChangelog(_:))
        button.alignment = .left
        button.sizeToFit()
        button.frame.origin = .zero
        changelogURL = destination

        // The alert centers its accessory view and sizes itself to the widest element, so
        // the link rides in a carrier as wide as the text block above it. Left-aligning it
        // inside the carrier lines it up with the two lines of text; sizing the carrier to
        // the message rather than wider keeps the whole alert thin.
        let carrier = NSView(frame: NSRect(x: 0, y: 0, width: 216, height: 18))
        carrier.addSubview(button)
        return carrier
    }

    private var changelogURL: URL?

    @objc private func openChangelog(_ sender: Any?) {
        guard let changelogURL else { return }
        NSWorkspace.shared.open(changelogURL)
    }

    private static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "an earlier version"
    }

    // MARK: - Everything else is Sparkle's

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func showUpdateInFocus() {
        standard.showUpdateInFocus()
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }
}
