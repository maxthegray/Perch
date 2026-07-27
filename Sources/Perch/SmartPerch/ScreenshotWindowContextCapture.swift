import AppKit
import CoreGraphics
import Darwin
import SmartPerchCore

/// Captures the macOS window that visibly occupies a fresh screenshot's saved global
/// rectangle. This runs only when a screenshot first arrives; naming and replay use
/// the persisted value and never inspect the live desktop again.
@MainActor
enum ScreenshotWindowContextCapture {
    private static let globalRectAttribute =
        "com.apple.metadata:kMDItemScreenCaptureGlobalRect"

    static func captureFreshContext(
        for screenshotURL: URL,
        now: Date = Date(),
        freshnessLimit: TimeInterval = 10
    ) -> ScreenshotCaptureContext? {
        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey, .creationDateKey
        ]
        guard let values = try? screenshotURL.resourceValues(forKeys: keys),
              let fileDate = values.addedToDirectoryDate ?? values.creationDate,
              now.timeIntervalSince(fileDate) >= -2,
              now.timeIntervalSince(fileDate) <= freshnessLimit
        else {
            return nil
        }
        return captureContext(for: screenshotURL, capturedAt: now)
    }

    static func captureContext(
        for screenshotURL: URL,
        capturedAt: Date = Date()
    ) -> ScreenshotCaptureContext? {
        guard let attributeData = extendedAttributeData(
            named: globalRectAttribute,
            at: screenshotURL
        ),
        let captureRect = captureRect(fromPropertyListData: attributeData)
        else {
            return nil
        }

        let windows = onScreenWindows()
        return ScreenshotWindowContextMatcher.match(
            captureRect: captureRect,
            windows: windows,
            capturedAtMilliseconds: Int64(
                (capturedAt.timeIntervalSince1970 * 1_000).rounded()
            )
        )
    }

    /// Internal for deterministic tests using synthetic binary plists.
    static func captureRect(
        fromPropertyListData data: Data
    ) -> ScreenshotScreenRect? {
        guard let propertyList = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else {
            return nil
        }

        if let array = propertyList as? [Any],
           let numbers = numericValues(in: array),
           numbers.count >= 4 {
            return makeRect(numbers)
        }

        if let dictionary = propertyList as? [String: Any] {
            let keys = [
                ["x", "X"],
                ["y", "Y"],
                ["width", "Width", "w", "W"],
                ["height", "Height", "h", "H"]
            ]
            let numbers = keys.compactMap { alternatives -> Double? in
                alternatives.lazy.compactMap {
                    number(from: dictionary[$0])
                }.first
            }
            if numbers.count == 4 {
                return makeRect(numbers)
            }
        }

        if let string = propertyList as? String {
            let pattern = #"-?\d+(?:\.\d+)?"#
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let matches = expression.matches(
                in: string,
                range: NSRange(string.startIndex..<string.endIndex, in: string)
            )
            let numbers = matches.compactMap { match -> Double? in
                guard let range = Range(match.range, in: string) else { return nil }
                return Double(string[range])
            }
            if numbers.count >= 4 {
                return makeRect(numbers)
            }
        }

        return nil
    }

    private static func makeRect(_ numbers: [Double]) -> ScreenshotScreenRect? {
        let rect = ScreenshotScreenRect(
            x: numbers[0],
            y: numbers[1],
            width: numbers[2],
            height: numbers[3]
        )
        return rect.area > 0 ? rect : nil
    }

    private static func numericValues(in values: [Any]) -> [Double]? {
        let numbers = values.compactMap(number(from:))
        return numbers.count == values.count ? numbers : nil
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func extendedAttributeData(
        named name: String,
        at url: URL
    ) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            return name.withCString { attributeName -> Data? in
                let size = getxattr(path, attributeName, nil, 0, 0, 0)
                guard size > 0 else { return nil }

                var data = Data(count: size)
                let bytesRead = data.withUnsafeMutableBytes { buffer in
                    getxattr(
                        path,
                        attributeName,
                        buffer.baseAddress,
                        size,
                        0,
                        0
                    )
                }
                guard bytesRead == size else { return nil }
                return data
            }
        }
    }

    private static func onScreenWindows() -> [ScreenshotWindowSnapshot] {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return rawWindows.enumerated().compactMap { zIndex, info in
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0,
                  let processNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue,
                  let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue
            else {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            guard
                  frame.width >= 100,
                  frame.height >= 80
            else {
                return nil
            }

            let processIdentifier = processNumber.intValue
            let application = NSRunningApplication(
                processIdentifier: pid_t(processIdentifier)
            )
            let bundleIdentifier = application?.bundleIdentifier
            let resolvedOwnerName = application?.localizedName ?? ownerName
            guard !shouldIgnore(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                ownerName: resolvedOwnerName
            ) else {
                return nil
            }

            let rawTitle = info[kCGWindowName as String] as? String
            let title = rawTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return ScreenshotWindowSnapshot(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifier,
                ownerName: resolvedOwnerName,
                windowTitle: title?.isEmpty == false ? title : nil,
                frame: ScreenshotScreenRect(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height
                ),
                zIndex: zIndex
            )
        }
    }

    private static func shouldIgnore(
        processIdentifier: Int,
        bundleIdentifier: String?,
        ownerName: String
    ) -> Bool {
        if processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }
        return ignoredOwnerNames.contains(ownerName.lowercased())
    }

    private static let ignoredOwnerNames: Set<String> = [
        "control center",
        "dock",
        "notification center",
        "perch",
        "screencaptureui",
        "systemuiserver",
        "window server"
    ]
}
