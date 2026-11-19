import Foundation

/// Where macOS saves screenshots, read from the Screenshot app's preferences
/// (`com.apple.screencapture`). Unset means the Desktop.
enum ScreenshotLocation {
    /// True when screenshots go only to the clipboard and never become files.
    static var savesToClipboard: Bool {
        (preference("target") as? String) == "clipboard"
    }

    static var folder: URL {
        guard let path = preference("location") as? String, !path.isEmpty else {
            return desktop
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            .standardizedFileURL
    }

    /// The screenshot folder when it is somewhere Perch does not already watch.
    static var extraFolder: URL? {
        let folder = folder
        let watched = [desktop, downloads].map { $0.resolvingSymlinksInPath().path }
        return watched.contains(folder.resolvingSymlinksInPath().path) ? nil : folder
    }

    private static var desktop: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    private static func preference(_ key: String) -> Any? {
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
        return CFPreferencesCopyAppValue(key as CFString, "com.apple.screencapture" as CFString)
    }
}
