import AppKit
import CoreGraphics
import SmartPerchCore

/// One-shot destination lookup for a successful drag. It uses the ordinary Core
/// Graphics window list and does not require Accessibility permission.
@MainActor
enum RouteDestinationResolver {
    static func application(atAppKitScreenPoint screenPoint: NSPoint) -> RouteDestination? {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let coreGraphicsPoint = coreGraphicsPoint(from: screenPoint)
        for info in rawWindows {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0,
                  let processNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let frame = frame(from: bounds),
                  frame.contains(coreGraphicsPoint)
            else {
                continue
            }

            let processIdentifier = pid_t(processNumber.intValue)
            guard processIdentifier != getpid() else { continue }

            let application = NSRunningApplication(processIdentifier: processIdentifier)
            let bundleIdentifier = application?.bundleIdentifier
            if bundleIdentifier == Bundle.main.bundleIdentifier {
                continue
            }

            let ownerName = (application?.localizedName
                ?? info[kCGWindowOwnerName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ownerName, !ownerName.isEmpty else { continue }

            return .application(
                bundleIdentifier: bundleIdentifier,
                name: ownerName
            )
        }
        return nil
    }

    /// AppKit global screen coordinates grow upward from the main display's bottom;
    /// Core Graphics window bounds grow downward from its top.
    private static func coreGraphicsPoint(from point: NSPoint) -> CGPoint {
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let mainAppKitFrame = NSScreen.screens.first?.frame
            ?? NSRect(
                x: mainDisplayBounds.minX,
                y: mainDisplayBounds.minY,
                width: mainDisplayBounds.width,
                height: mainDisplayBounds.height
            )
        return CGPoint(
            x: point.x,
            y: mainDisplayBounds.minY + mainAppKitFrame.maxY - point.y
        )
    }

    private static func frame(from bounds: [String: NSNumber]) -> CGRect? {
        guard let x = bounds["X"]?.doubleValue,
              let y = bounds["Y"]?.doubleValue,
              let width = bounds["Width"]?.doubleValue,
              let height = bounds["Height"]?.doubleValue,
              width > 0,
              height > 0
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
