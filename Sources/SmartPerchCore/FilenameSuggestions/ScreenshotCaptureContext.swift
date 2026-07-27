import Foundation

/// A rectangle in the global Core Graphics screen coordinate space.
public struct ScreenshotScreenRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Double {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    public func contains(x: Double, y: Double) -> Bool {
        x >= self.x
            && x <= self.x + width
            && y >= self.y
            && y <= self.y + height
    }
}

/// One ordinary on-screen window, captured front-to-back at screenshot arrival time.
public struct ScreenshotWindowSnapshot: Equatable, Sendable {
    public let processIdentifier: Int
    public let bundleIdentifier: String?
    public let ownerName: String
    public let windowTitle: String?
    public let frame: ScreenshotScreenRect
    public let zIndex: Int

    public init(
        processIdentifier: Int,
        bundleIdentifier: String?,
        ownerName: String,
        windowTitle: String?,
        frame: ScreenshotScreenRect,
        zIndex: Int
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.frame = frame
        self.zIndex = zIndex
    }
}

/// Window identity preserved with a screenshot event before the desktop changes.
public struct ScreenshotCaptureContext: Codable, Equatable, Sendable {
    public let capturedAtMilliseconds: Int64
    public let captureRect: ScreenshotScreenRect
    public let ownerProcessIdentifier: Int
    public let ownerBundleIdentifier: String?
    public let ownerName: String
    public let windowTitle: String?
    public let matchedWindowRect: ScreenshotScreenRect
    public let visibleCoverage: Double

    public init(
        capturedAtMilliseconds: Int64,
        captureRect: ScreenshotScreenRect,
        ownerProcessIdentifier: Int,
        ownerBundleIdentifier: String?,
        ownerName: String,
        windowTitle: String?,
        matchedWindowRect: ScreenshotScreenRect,
        visibleCoverage: Double
    ) {
        self.capturedAtMilliseconds = capturedAtMilliseconds
        self.captureRect = captureRect
        self.ownerProcessIdentifier = ownerProcessIdentifier
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.matchedWindowRect = matchedWindowRect
        self.visibleCoverage = visibleCoverage
    }
}

/// Finds the app that visibly owns most of a screenshot selection.
///
/// Sampling honors window z-order, unlike a simple rectangle intersection that would
/// incorrectly choose a full-screen browser hidden behind a smaller foreground app.
public enum ScreenshotWindowContextMatcher {
    public static func match(
        captureRect: ScreenshotScreenRect,
        windows: [ScreenshotWindowSnapshot],
        capturedAtMilliseconds: Int64,
        minimumVisibleCoverage: Double = 0.55,
        samplesPerAxis: Int = 24
    ) -> ScreenshotCaptureContext? {
        guard captureRect.area > 0,
              samplesPerAxis > 0
        else {
            return nil
        }

        let orderedWindows = windows
            .filter { $0.frame.area > 0 && !$0.ownerName.isEmpty }
            .sorted { $0.zIndex < $1.zIndex }
        guard !orderedWindows.isEmpty else { return nil }

        struct OwnerKey: Hashable {
            let processIdentifier: Int
            let identity: String
        }

        var ownerCounts: [OwnerKey: Int] = [:]
        var windowCounts: [Int: Int] = [:]
        var ownerByWindowIndex: [Int: OwnerKey] = [:]
        let totalSamples = samplesPerAxis * samplesPerAxis

        for row in 0..<samplesPerAxis {
            let y = captureRect.y
                + (Double(row) + 0.5) * captureRect.height / Double(samplesPerAxis)
            for column in 0..<samplesPerAxis {
                let x = captureRect.x
                    + (Double(column) + 0.5) * captureRect.width / Double(samplesPerAxis)
                guard let windowIndex = orderedWindows.firstIndex(where: {
                    $0.frame.contains(x: x, y: y)
                }) else {
                    continue
                }

                let window = orderedWindows[windowIndex]
                let key = OwnerKey(
                    processIdentifier: window.processIdentifier,
                    identity: window.bundleIdentifier ?? window.ownerName.lowercased()
                )
                ownerCounts[key, default: 0] += 1
                windowCounts[windowIndex, default: 0] += 1
                ownerByWindowIndex[windowIndex] = key
            }
        }

        guard let dominantOwner = ownerCounts.max(by: {
            if $0.value != $1.value { return $0.value < $1.value }
            return $0.key.identity > $1.key.identity
        }) else {
            return nil
        }

        let visibleCoverage = Double(dominantOwner.value) / Double(totalSamples)
        guard visibleCoverage >= minimumVisibleCoverage else { return nil }

        let representativeIndex = windowCounts
            .filter { ownerByWindowIndex[$0.key] == dominantOwner.key }
            .max {
                if $0.value != $1.value { return $0.value < $1.value }
                return orderedWindows[$0.key].zIndex > orderedWindows[$1.key].zIndex
            }?
            .key
        guard let representativeIndex else { return nil }
        let representative = orderedWindows[representativeIndex]

        return ScreenshotCaptureContext(
            capturedAtMilliseconds: capturedAtMilliseconds,
            captureRect: captureRect,
            ownerProcessIdentifier: representative.processIdentifier,
            ownerBundleIdentifier: representative.bundleIdentifier,
            ownerName: representative.ownerName,
            windowTitle: representative.windowTitle,
            matchedWindowRect: representative.frame,
            visibleCoverage: visibleCoverage
        )
    }
}
