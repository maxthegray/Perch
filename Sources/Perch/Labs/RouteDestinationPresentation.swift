import Foundation
import SmartPerchCore

/// How a learned destination is named in the UI. Rows are narrow, so this is the
/// shortest label that still tells the user where the item is going.
enum RouteDestinationPresentation {
    /// The folder's own name, with the two paths that would otherwise read as a bare
    /// account name or an empty component spelled out.
    static func shortName(for destination: RouteDestination) -> String {
        switch destination {
        case let .folder(path):
            return folderName(atPath: path)
        case let .application(_, name):
            return name
        }
    }

    static func folderURL(for destination: RouteDestination) -> URL? {
        guard case let .folder(path) = destination else { return nil }
        return URL(fileURLWithPath: (path as NSString).standardizingPath, isDirectory: true)
    }

    private static func folderName(atPath path: String) -> String {
        let standardized = (path as NSString).standardizingPath
        if standardized == NSHomeDirectory() {
            return "Home"
        }
        if standardized == "/" {
            return "Macintosh HD"
        }
        let name = (standardized as NSString).lastPathComponent
        return name.isEmpty ? standardized : name
    }
}
